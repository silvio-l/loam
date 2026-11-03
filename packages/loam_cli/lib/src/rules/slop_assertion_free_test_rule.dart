import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../loader/project_loader.dart';
import '../model/anchor.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import '../model/project_path.dart';
import 'generated_file.dart';
import 'rule.dart';

/// A plain [Rule], not a [FileRule]: the check reads resolved elements and
/// follows project helper functions across files, so it needs a full
/// (resolved) load.
///
/// Detects `test(...)` / `testWidgets(...)` whose body never checks anything.
///
/// Rule ID: `slop-assertion-free-test`
///
/// A test name claims a behaviour ("restores the cache after a restart"); a
/// body that only runs the code under test proves nothing — it stays green
/// whatever the code does, short of throwing. Agents that "add tests" often
/// leave such bodies behind. A finding is emitted for a call of `test` or
/// `testWidgets` — resolved on the element model to `package:test`,
/// `package:test_api`, `package:test_core` or `package:flutter_test`, never
/// matched by name alone — whose body (a function literal, or a reference to
/// a project function) contains **no assertion**.
///
/// **What counts as an assertion**, anywhere in the body, in a closure inside
/// it, or in a project function/method the body calls (resolved, any loaded
/// file, at most [maxHelperDepth] hops, cycle-safe):
/// - `expect`, `expectLater`, `fail`, `markTestSkipped`, `expectAsync*` from
///   the test packages (`test`, `test_api`, `test_core`, `flutter_test`,
///   `matcher`);
/// - `verify`, `verifyNever`, `verifyInOrder`, `verifyNoMoreInteractions`,
///   `verifyZeroInteractions` and any other `verify*` from `mockito` /
///   `mocktail`; `check` from `package:checks`; every call into
///   `golden_toolkit` (screen golden matchers);
/// - a function whose name is listed under `slop_assertion_free_test:
///   assertion_functions:` in `loam.yaml`, wherever it is declared;
/// - an `assert(...)` statement or a `throw` written in the test body itself
///   — a hand-written failure (not in helpers: production code throws as
///   part of its normal behaviour).
///
/// A call of a function-typed parameter, field or variable that the rule
/// cannot look into (`await body(tester)` in a `testWidgets` wrapper,
/// `c.expect(button)`) counts as an assertion too: the checks live where the
/// callback is supplied.
///
/// Calls into other packages (`tester.pumpWidget`, `container.read`, ...) are
/// **not** assertions: almost every test makes them, so counting them would
/// silence the rule. A callee that cannot be resolved at all is counted only
/// when its name is one of the framework assertions above (broken setup must
/// not create findings).
///
/// Deliberately **not** reported: tests with a `skip:` argument (other than a
/// literal `false`), tests whose body is not a function literal and cannot be
/// resolved to a project function, and generated files.
///
/// **Semantic anchor (fingerprint stability):**
/// `enclosingMember:assertion-free-test:contentHash:n` — content is the group
/// chain plus the test description, so a body edit, a line shift or a test
/// reordering never changes it; only identical descriptions in the same scope
/// are told apart by order.
///
/// **Finding contract:** `severity`: [Severity.info], `kind`:
/// `'assertion-free-test'`, `remedy`: imperative fix instruction.
///
/// **Suppression:**
/// `// loam-ignore: slop-assertion-free-test – <reason>` on or before the
/// test call.
class SlopAssertionFreeTestRule implements Rule {
  /// The stable rule ID for [SlopAssertionFreeTestRule].
  static const String ruleIdStatic = 'slop-assertion-free-test';

  /// How many project-function hops from the test body are followed.
  static const int maxHelperDepth = 3;

  /// Creates a [SlopAssertionFreeTestRule] rooted at [projectRoot].
  ///
  /// [assertionFunctions] are extra function names (`loam.yaml`:
  /// `slop_assertion_free_test.assertion_functions`) that count as assertion.
  const SlopAssertionFreeTestRule({
    required this.projectRoot,
    this.assertionFunctions = const [],
  });

  /// Absolute path of the project being analysed.
  final String projectRoot;

  /// Project-specific assertion helpers, matched by function name.
  final List<String> assertionFunctions;

  @override
  String get ruleId => ruleIdStatic;

  @override
  RuleCategory get category => RuleCategory.slop;

  @override
  List<Finding> run(ProjectLoadResult result) {
    final files = [
      for (final f in result.resolved)
        if (!isGeneratedDartFile(f.path)) f,
    ];
    final bodies = <Element, FunctionBody>{};
    for (final file in files) {
      file.result.unit.accept(_BodyIndexer(bodies));
    }
    final analyzer = _AssertionSearch(bodies, assertionFunctions.toSet());

    final findings = <Finding>[];
    for (final file in files) {
      file.result.unit.accept(
        _TestVisitor(
          relativePath: projectRelativePosixPath(file.path, projectRoot),
          search: analyzer,
          bodies: bodies,
          findings: findings,
        ),
      );
    }
    return findings;
  }
}

/// Packages whose `test`/`testWidgets` declare a test case.
const _testDeclarers = {'test', 'test_api', 'test_core', 'flutter_test'};

/// Packages whose `expect`-family calls are assertions.
const _expectPackages = {
  'test',
  'test_api',
  'test_core',
  'flutter_test',
  'matcher',
  'integration_test',
};

const _expectNames = {'expect', 'expectLater', 'fail', 'markTestSkipped'};

const _verifyPackages = {'mockito', 'mocktail'};

String? _packageOf(Element? element) {
  final uri = element?.library?.uri;
  if (uri == null || uri.scheme != 'package' || uri.pathSegments.isEmpty) {
    return null;
  }
  return uri.pathSegments.first;
}

bool _isExpectName(String name) =>
    _expectNames.contains(name) || name.startsWith('expectAsync');

bool _isVerifyName(String name) => name.startsWith('verify');

/// Maps every function, method and closure-valued variable declared in the
/// loaded files to its body, so helper calls can be followed.
class _BodyIndexer extends RecursiveAstVisitor<void> {
  _BodyIndexer(this.bodies);

  final Map<Element, FunctionBody> bodies;

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element != null) {
      bodies[element.baseElement] = node.functionExpression.body;
    }
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final element = node.declaredFragment?.element;
    if (element != null) bodies[element.baseElement] = node.body;
    super.visitMethodDeclaration(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    final init = node.initializer;
    final element = node.declaredFragment?.element;
    if (element != null && init is FunctionExpression) {
      bodies[element] = init.body;
    }
    super.visitVariableDeclaration(node);
  }
}

/// Decides whether a function body asserts, following project helpers.
class _AssertionSearch {
  _AssertionSearch(this._bodies, this._extraNames);

  final Map<Element, FunctionBody> _bodies;
  final Set<String> _extraNames;
  final Set<Element> _onStack = {};
  final Map<(Element, int), bool> _cache = {};
  int _cuts = 0;

  /// The depth the test body itself is searched with.
  static const int _top = SlopAssertionFreeTestRule.maxHelperDepth;

  /// Whether [body] — or a project function it calls, up to [depth] hops —
  /// contains an assertion.
  bool asserts(FunctionBody body, int depth) {
    final scan = _Scan(this, countsFailures: depth == _top);
    body.accept(scan);
    if (scan.found) return true;
    if (depth <= 0) return false;
    for (final callee in scan.callees) {
      if (_assertsVia(callee, depth - 1)) return true;
    }
    return false;
  }

  bool _assertsVia(Element callee, int depth) {
    final body = _bodies[callee];
    if (body == null) return false;
    final key = (callee, depth);
    final cached = _cache[key];
    if (cached != null) return cached;
    if (!_onStack.add(callee)) {
      _cuts++;
      return false;
    }
    final cutsBefore = _cuts;
    final result = asserts(body, depth);
    _onStack.remove(callee);
    // A "no" computed while a cycle was cut may be incomplete: not cached.
    if (result || _cuts == cutsBefore) _cache[key] = result;
    return result;
  }

  /// Whether a call of [name] resolved to [element] is an assertion by itself.
  bool isAssertionCall(String name, Element? element) {
    if (_extraNames.contains(name)) return true;
    if (element == null) return _isExpectName(name);
    final package = _packageOf(element);
    if (package == null) return false;
    if (_expectPackages.contains(package)) return _isExpectName(name);
    if (_verifyPackages.contains(package)) return _isVerifyName(name);
    if (package == 'checks') return name == 'check';
    return package == 'golden_toolkit';
  }
}

/// Collects assertion hits and project callees of one body.
class _Scan extends RecursiveAstVisitor<void> {
  _Scan(this._search, {required this.countsFailures});

  final _AssertionSearch _search;

  /// Whether `assert`/`throw` count: only in the test body itself — a helper
  /// in production code throws as part of its normal behaviour.
  final bool countsFailures;
  bool found = false;
  final List<Element> callees = [];

  @override
  void visitAssertStatement(AssertStatement node) {
    if (countsFailures) found = true;
  }

  @override
  void visitThrowExpression(ThrowExpression node) {
    if (countsFailures) found = true;
    super.visitThrowExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    final element = node.methodName.element;
    if (_search.isAssertionCall(node.methodName.name, element)) {
      found = true;
      return;
    }
    if (_isOpaqueCallback(element)) {
      found = true;
      return;
    }
    _noteCallee(element);
    super.visitMethodInvocation(node);
  }

  @override
  void visitFunctionExpressionInvocation(FunctionExpressionInvocation node) {
    final function = node.function;
    if (function is SimpleIdentifier) {
      if (_search.isAssertionCall(function.name, function.element)) {
        found = true;
        return;
      }
      if (_isOpaqueCallback(function.element)) {
        found = true;
        return;
      }
      _noteCallee(function.element);
    }
    super.visitFunctionExpressionInvocation(node);
  }

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    // A tear-off handed on (`group.run(check)`) is followed like a call.
    if (node.parent is! MethodInvocation &&
        node.parent is! FunctionExpressionInvocation) {
      final element = node.element;
      if (element is ExecutableElement || element is VariableElement) {
        if (_search._bodies.containsKey(_base(element))) {
          _noteCallee(element);
        }
      }
    }
    super.visitSimpleIdentifier(node);
  }

  /// A call of a function-typed parameter, field or variable whose value the
  /// rule cannot see (`await body(tester)`, `c.expect(button)`): the checks
  /// live where the callback is supplied, so the call counts as one.
  bool _isOpaqueCallback(Element? e) {
    if (e is! VariableElement && e is! GetterElement) return false;
    if (e is GetterElement && !e.isOriginVariable) return false;
    return !_search._bodies.containsKey(e);
  }

  Element? _base(Element? e) => e is ExecutableElement ? e.baseElement : e;

  void _noteCallee(Element? element) {
    final base = _base(element);
    if (base != null && !callees.contains(base)) callees.add(base);
  }
}

class _TestVisitor extends RecursiveAstVisitor<void> {
  _TestVisitor({
    required this.relativePath,
    required this.search,
    required this.bodies,
    required this.findings,
  });

  final String relativePath;
  final _AssertionSearch search;
  final Map<Element, FunctionBody> bodies;
  final List<Finding> findings;
  final AnchorCounter _anchors = AnchorCounter();

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.target != null) return;
    final name = node.methodName.name;
    if (name != 'test' && name != 'testWidgets') return;
    if (!_testDeclarers.contains(_packageOf(node.methodName.element))) return;

    final args = node.argumentList.arguments;
    final positional = [
      for (final a in args)
        if (a is Expression) a,
    ];
    if (positional.length < 2) return;
    if (_isSkipped(args)) return;

    final body = _bodyOf(positional[1]);
    if (body == null) return;
    if (search.asserts(body, SlopAssertionFreeTestRule.maxHelperDepth)) return;

    _addFinding(node, positional.first);
  }

  /// `skip: <anything but the literal false>` disables the test.
  bool _isSkipped(NodeList<Argument> args) {
    for (final a in args) {
      if (a is NamedArgument && a.name.lexeme == 'skip') {
        final e = a.argumentExpression;
        return !(e is BooleanLiteral && !e.value);
      }
    }
    return false;
  }

  FunctionBody? _bodyOf(Expression e) {
    if (e is FunctionExpression) return e.body;
    if (e is SimpleIdentifier) {
      final el = e.element;
      final base = el is ExecutableElement ? el.baseElement : el;
      return base == null ? null : bodies[base];
    }
    return null;
  }

  void _addFinding(MethodInvocation node, Expression description) {
    final groups = _groupChain(node);
    final anchor = _anchors.next(
      '${enclosingMemberName(node)}:assertion-free-test',
      '${groups.join('>')}>${normalizedSource(description)}',
    );
    final fingerprint = computeFingerprint(
      ruleId: SlopAssertionFreeTestRule.ruleIdStatic,
      relativePath: relativePath,
      semanticAnchor: anchor,
    );
    final lineInfo = (node.root as CompilationUnit).lineInfo;
    final location = lineInfo.getLocation(node.offset);
    final title = description is SimpleStringLiteral
        ? '`${description.value}`'
        : 'this test';

    findings.add(
      Finding(
        ruleId: SlopAssertionFreeTestRule.ruleIdStatic,
        severity: Severity.info,
        filePath: relativePath,
        line: location.lineNumber,
        column: location.columnNumber,
        message:
            '$title never asserts anything (`expect`, `verify`, `check`, ...) '
            '— it stays green whatever the code under test returns.',
        fingerprint: fingerprint,
        kind: 'assertion-free-test',
        remedy:
            'Assert the behaviour the test name promises, e.g. '
            '`expect(result, equals(expected))`, or `verify(...)` for an '
            'interaction. If "does not throw" is the whole point, say so with '
            '`expect(() => ..., returnsNormally)`. If the body is a helper '
            'that asserts under another name, list it under '
            '`slop_assertion_free_test.assertion_functions` in `loam.yaml`.',
      ),
    );
  }

  /// Source of the enclosing `group(...)` descriptions, outermost first.
  List<String> _groupChain(AstNode node) {
    final chain = <String>[];
    for (AstNode? n = node.parent; n != null; n = n.parent) {
      if (n is MethodInvocation &&
          n.target == null &&
          n.methodName.name == 'group' &&
          n.argumentList.arguments.isNotEmpty) {
        chain.insert(0, normalizedSource(n.argumentList.arguments.first));
      }
    }
    return chain;
  }
}

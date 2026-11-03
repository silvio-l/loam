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

/// A plain [Rule], not a [FileRule]: the check reads resolved elements, so it
/// needs a full (resolved) load.
///
/// Detects `expect`/`expectLater` calls that cannot detect any regression.
///
/// Rule ID: `slop-tautological-assertion`
///
/// Agents that "make the tests green" often leave assertions like
/// `expect(true, isTrue)` behind. They pass whatever the code under test does.
/// A finding is emitted for a call of `expect` or `expectLater` — resolved on
/// the element model to `package:test`, `package:test_api`,
/// `package:flutter_test` or `package:matcher`, never matched by name alone —
/// when
///
/// 1. the **actual** value is a constant literal (`true`, `1`, `'a'`, `null`,
///    `-1`, or a list/set/map/record literal built only from such constants)
///    **and** the **matcher** is a literal, `equals(<constant>)` or one of the
///    constant matchers `isTrue`, `isFalse`, `isNull`, `isNotNull`,
///    `isEmpty`, `isNotEmpty`; or
/// 2. actual and matcher are the **same** chain of variables and stored
///    fields (`expect(x, x)`, `expect(a.b, equals(a.b))`).
///
/// Deliberately **not** reported: collection literals that contain an
/// identifier, a `for`/`if` element or a spread (`[for (r in rows) r.id]`),
/// records with identifiers, interpolated strings, calls or computed getters
/// compared with themselves (`expect(next(), next())`, `expect(a.hashCode,
/// a.hashCode)` may be a deliberate stability check), and `expect(x, isTrue)`.
///
/// **Semantic anchor (fingerprint stability):**
/// `enclosingMemberName:expect:contentHash:n` — content is the normalised
/// token text of the call, `n` counts only earlier identical calls in the same
/// member.
///
/// **Suppression:**
/// `// loam-ignore: slop-tautological-assertion – <reason>`.
class SlopTautologicalAssertionRule implements Rule {
  /// The stable rule ID for [SlopTautologicalAssertionRule].
  static const String ruleIdStatic = 'slop-tautological-assertion';

  /// Creates a [SlopTautologicalAssertionRule] rooted at [projectRoot].
  const SlopTautologicalAssertionRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  final String projectRoot;

  @override
  String get ruleId => ruleIdStatic;

  @override
  RuleCategory get category => RuleCategory.slop;

  @override
  List<Finding> run(ProjectLoadResult result) {
    final findings = <Finding>[];
    for (final file in result.resolved) {
      if (isGeneratedDartFile(file.path)) continue;
      file.result.unit.accept(
        _TautologyVisitor(
          relativePath: projectRelativePosixPath(file.path, projectRoot),
          findings: findings,
        ),
      );
    }
    return findings;
  }
}

/// Packages whose `expect`/matchers count as test assertions.
const _testPackages = {'test', 'test_api', 'flutter_test', 'matcher'};

/// Matchers whose outcome depends only on a constant actual value.
const _constantMatchers = {
  'isTrue',
  'isFalse',
  'isNull',
  'isNotNull',
  'isEmpty',
  'isNotEmpty',
};

bool _inTestPackage(Element? element) {
  final uri = element?.library?.uri;
  return uri != null &&
      uri.scheme == 'package' &&
      uri.pathSegments.isNotEmpty &&
      _testPackages.contains(uri.pathSegments.first);
}

/// Whether [e] is a constant literal: its value cannot depend on any code.
bool _isConstantLiteral(Expression e) => switch (e) {
  BooleanLiteral() ||
  IntegerLiteral() ||
  DoubleLiteral() ||
  NullLiteral() => true,
  SimpleStringLiteral() => true,
  AdjacentStrings() => e.strings.every(_isConstantLiteral),
  StringInterpolation() => false,
  ParenthesizedExpression() => _isConstantLiteral(e.expression),
  PrefixExpression() =>
    e.operator.lexeme == '-' &&
        (e.operand is IntegerLiteral || e.operand is DoubleLiteral),
  ListLiteral() => e.elements.every(_isConstantElement),
  SetOrMapLiteral() => e.elements.every(_isConstantElement),
  RecordLiteral() => e.fields.every(
    (f) => _isConstantLiteral(f.fieldExpression),
  ),
  _ => false,
};

bool _isConstantElement(CollectionElement e) => switch (e) {
  Expression() => _isConstantLiteral(e),
  MapLiteralEntry() => _isConstantLiteral(e.key) && _isConstantLiteral(e.value),
  _ => false,
};

/// A chain of plain variables and stored fields: `x`, `a.b`, `this.a`,
/// `a?.b`. Reading one twice always yields the same value. A computed getter
/// (`hashCode`, `length`, `DateTime.now`-style accessors) is not accepted:
/// `expect(a.hashCode, a.hashCode)` is a deliberate stability check.
bool _isStoredValueChain(Expression e) => switch (e) {
  SimpleIdentifier() => _isStoredValue(e.element),
  PrefixedIdentifier() =>
    _isStoredValue(e.prefix.element) && _isStoredValue(e.identifier.element),
  ThisExpression() => true,
  PropertyAccess() =>
    e.target != null &&
        _isStoredValueChain(e.target!) &&
        _isStoredValue(e.propertyName.element),
  ParenthesizedExpression() => _isStoredValueChain(e.expression),
  _ => false,
};

bool _isStoredValue(Element? element) => switch (element) {
  GetterElement() => element.isOriginVariable,
  VariableElement() => true,
  _ => false,
};

List<Expression> _positional(ArgumentList list) => [
  for (final a in list.arguments)
    if (a is Expression) a,
];

class _TautologyVisitor extends RecursiveAstVisitor<void> {
  _TautologyVisitor({required this.relativePath, required this.findings});

  final String relativePath;
  final List<Finding> findings;
  final AnchorCounter _anchors = AnchorCounter();

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.target != null) return;
    final name = node.methodName.name;
    if (name != 'expect' && name != 'expectLater') return;
    if (!_inTestPackage(node.methodName.element)) return;

    final args = _positional(node.argumentList);
    if (args.length < 2) return;
    final actual = args[0];
    final matcher = args[1];

    if (_isTautology(actual, matcher)) _addFinding(node);
  }

  bool _isTautology(Expression actual, Expression matcher) {
    final inner = _equalsArgument(matcher);
    if (_isStoredValueChain(actual) &&
        _isStoredValueChain(inner ?? matcher) &&
        _sameChain(actual, inner ?? matcher)) {
      return true;
    }
    if (!_isConstantLiteral(actual)) return false;
    if (inner != null) return _isConstantLiteral(inner);
    return _isConstantLiteral(matcher) || _isConstantMatcher(matcher);
  }

  bool _sameChain(Expression a, Expression b) => _chainText(a) == _chainText(b);

  String _chainText(Expression e) =>
      e.toSource().replaceAll(RegExp(r'[\s()]'), '').replaceAll('?.', '.');

  /// The argument of `equals(<arg>)` when [e] is a resolved matcher `equals`.
  Expression? _equalsArgument(Expression e) {
    if (e is! MethodInvocation ||
        e.target != null ||
        e.methodName.name != 'equals' ||
        !_inTestPackage(e.methodName.element)) {
      return null;
    }
    final positional = _positional(e.argumentList);
    return positional.isEmpty ? null : positional.first;
  }

  bool _isConstantMatcher(Expression e) {
    final SimpleIdentifier id;
    if (e is SimpleIdentifier) {
      id = e;
    } else if (e is PrefixedIdentifier) {
      id = e.identifier;
    } else {
      return false;
    }
    return _constantMatchers.contains(id.name) && _inTestPackage(id.element);
  }

  void _addFinding(MethodInvocation node) {
    final anchor = _anchors.next(
      '${enclosingMemberName(node)}:expect',
      normalizedSource(node),
    );
    final fingerprint = computeFingerprint(
      ruleId: SlopTautologicalAssertionRule.ruleIdStatic,
      relativePath: relativePath,
      semanticAnchor: anchor,
    );
    final lineInfo = (node.root as CompilationUnit).lineInfo;
    final location = lineInfo.getLocation(node.offset);

    findings.add(
      Finding(
        ruleId: SlopTautologicalAssertionRule.ruleIdStatic,
        severity: Severity.warning,
        filePath: relativePath,
        line: location.lineNumber,
        column: location.columnNumber,
        message:
            '`${node.methodName.name}` compares a constant with a constant '
            '(or a value with itself) — it stays green whatever the code '
            'under test does.',
        fingerprint: fingerprint,
        kind: 'tautological-assertion',
        remedy:
            'Assert on a value produced by the code under test, e.g. '
            '`expect(parse(input), equals(expected))`. If the check is '
            'meaningless, delete it. If it is intentional, suppress with '
            '`// loam-ignore: slop-tautological-assertion – <reason>`.',
      ),
    );
  }
}

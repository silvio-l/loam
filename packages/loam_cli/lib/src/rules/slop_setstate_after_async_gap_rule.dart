import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';

import '../loader/project_loader.dart';
import '../model/anchor.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'rule.dart';
import 'visit_file.dart';

/// A plain [Rule], not a [FileRule]: the check resolves `setState` on the
/// element model, so it needs a full (resolved) load.
///
/// Detects `setState(…)` that can run after the `State` left the tree.
///
/// Rule ID: `slop-setstate-after-async-gap`
///
/// Once a screen is closed, its `State` is unmounted; calling `setState` then
/// throws (`setState() called after dispose()`). The official lint
/// `use_build_context_synchronously` only covers `BuildContext`, not
/// `setState`. A finding is emitted for a call that resolves to `setState`
/// of Flutter's `State` (`package:flutter`, never matched by name alone),
/// called on `this`/`super` or without a target, when on its way back to the
/// start of the enclosing function it meets an async gap before a `mounted`
/// check:
///
/// - an `await` (or `await for`) in an earlier statement of the same or an
///   enclosing block, in the condition of an enclosing `if`/`while`/`?:`, or
///   in the `try` body when the call sits in `catch`/`finally`;
/// - the call sits in a callback passed to `Future.then`, `whenComplete` or
///   `catchError`.
///
/// A `mounted` check ends the search without a finding: an earlier statement
/// `if (…mounted…) return;` (or `throw`, `break`, `continue`, also in a
/// block), and an enclosing `if (…mounted…)`, `…mounted… ? … : …` or
/// `…mounted… && …` / `|| …`. Any mention of `mounted` (`mounted`,
/// `context.mounted`, `this.mounted`, negated or combined) counts, so an
/// unusual guard never produces a false positive.
///
/// The guard analysis follows the idea of the async-gap walk in the official
/// `use_build_context_synchronously` lint (Dart SDK `pkg/linter`, BSD-3-Clause,
/// Copyright the Dart project authors); the code here is written from scratch.
///
/// Deliberately **not** reported (unknown control flow): an earlier statement
/// that contains both an `await` and a `mounted` check, calls inside other
/// closures (`forEach`, `Future.delayed`, listeners, post-frame callbacks),
/// awaits on an earlier loop iteration, method tear-offs passed to `then`, and
/// projects' own wrappers (`safeSetState`) or `setState` overrides.
///
/// **Semantic anchor (fingerprint stability):**
/// `enclosingMemberName:setState:contentHash:n` — content is the normalised
/// token text of the call, `n` counts only earlier identical calls in the same
/// member.
///
/// **Suppression:**
/// `// loam-ignore: slop-setstate-after-async-gap – <reason>`.
class SlopSetStateAfterAsyncGapRule implements Rule {
  /// The stable rule ID for [SlopSetStateAfterAsyncGapRule].
  static const String ruleIdStatic = 'slop-setstate-after-async-gap';

  /// Creates a [SlopSetStateAfterAsyncGapRule] rooted at [projectRoot].
  const SlopSetStateAfterAsyncGapRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  final String projectRoot;

  @override
  String get ruleId => ruleIdStatic;

  @override
  RuleCategory get category => RuleCategory.slop;

  @override
  List<Finding> run(ProjectLoadResult result) => visitResolvedFiles(
    result,
    projectRoot,
    (relativePath, findings) =>
        _SetStateVisitor(relativePath: relativePath, findings: findings),
  );
}

/// Outcome of the walk from a `setState` call back to its function start.
enum _Gap {
  /// No async gap found, or the control flow is not understood.
  none,

  /// An async gap precedes the call with no `mounted` check in between.
  async,

  /// A `mounted` check precedes the call.
  guarded,
}

/// The `Future` methods whose callbacks run after an async gap.
const _futureCallbacks = {'then', 'whenComplete', 'catchError'};

bool _isFlutterStateSetState(Element? element) {
  if (element is! MethodElement || element.name != 'setState') return false;
  final owner = element.enclosingElement;
  if (owner is! InterfaceElement || owner.name != 'State') return false;
  final uri = element.library.uri;
  return uri.scheme == 'package' &&
      uri.pathSegments.isNotEmpty &&
      uri.pathSegments.first == 'flutter';
}

bool _isFutureMethod(Element? element) {
  if (element is! MethodElement) return false;
  final owner = element.enclosingElement;
  return owner is InterfaceElement &&
      owner.name == 'Future' &&
      element.library.uri.toString() == 'dart:async';
}

/// Whether [node] mentions `mounted` anywhere (`mounted`, `context.mounted`).
bool _mentionsMounted(AstNode node) {
  final finder = _MountedFinder();
  node.accept(finder);
  return finder.found;
}

/// Whether [node] contains an `await` that runs as part of [node] itself
/// (awaits inside nested closures do not count).
bool _containsAwait(AstNode node) {
  final finder = _AwaitFinder();
  node.accept(finder);
  return finder.found;
}

/// Whether [s] always leaves the current block (`return`, `throw`, `break`,
/// `continue`, or a block ending in one of them).
bool _terminates(Statement s) => switch (s) {
  ReturnStatement() || BreakStatement() || ContinueStatement() => true,
  ExpressionStatement(:final expression) =>
    expression is ThrowExpression || expression is RethrowExpression,
  Block(:final statements) =>
    statements.isNotEmpty && _terminates(statements.last),
  _ => false,
};

/// Whether an `await` in [s] can be followed by the statement after [s].
///
/// A branch that awaits and then always leaves the block (`if (c) { await
/// x; return; }`) never reaches the next statement, so it is no gap there.
bool _awaitReachesEnd(Statement s) {
  if (_terminates(s)) return false;
  return switch (s) {
    IfStatement(
      :final expression,
      :final thenStatement,
      :final elseStatement,
    ) =>
      _containsAwait(expression) ||
          _awaitReachesEnd(thenStatement) ||
          (elseStatement != null && _awaitReachesEnd(elseStatement)),
    Block(:final statements) => statements.any(_awaitReachesEnd),
    _ => _containsAwait(s),
  };
}

/// `if (…mounted…) return;` — an early exit when the state is gone.
bool _isExitGuard(Statement s) =>
    s is IfStatement &&
    _terminates(s.thenStatement) &&
    _mentionsMounted(s.expression);

/// Classifies the statements that run before [child] in [statements].
_Gap _scanPreceding(List<Statement> statements, AstNode child) {
  final index = statements.indexOf(child as Statement);
  for (var i = index - 1; i >= 0; i--) {
    final s = statements[i];
    if (_isExitGuard(s)) return _Gap.guarded;
    if (_awaitReachesEnd(s)) {
      // An await mixed with a mounted check (`if (c) { await x; if
      // (!mounted) return; }`) needs path analysis: stay silent.
      return _mentionsMounted(s) ? _Gap.none : _Gap.async;
    }
  }
  return _Gap.none;
}

/// Walks from [call] up to the start of its function and decides whether an
/// async gap precedes it without a `mounted` check.
_Gap _gapBefore(MethodInvocation call) {
  AstNode child = call;
  var parent = call.parent;
  while (parent != null) {
    final gap = _step(parent, child);
    if (gap != null) return gap;
    child = parent;
    parent = parent.parent;
  }
  return _Gap.none;
}

/// One step of [_gapBefore]: the verdict at [parent] (coming from [child]),
/// or `null` to keep walking up.
_Gap? _step(AstNode parent, AstNode child) => switch (parent) {
  Block(:final statements) => _precedingGap(statements, child),
  SwitchMember(:final statements) when child is Statement => _precedingGap(
    statements,
    child,
  ),
  IfStatement(:final expression) => _conditionGap(expression, child),
  ConditionalExpression(:final condition) => _conditionGap(condition, child),
  BinaryExpression(:final leftOperand) => _conditionGap(leftOperand, child),
  WhileStatement(:final condition) => _awaitGap(condition, child),
  ForStatement(:final awaitKeyword, :final forLoopParts) =>
    awaitKeyword != null && child != forLoopParts
        ? _Gap.async
        : _awaitGap(forLoopParts, child),
  CatchClause(parent: TryStatement(:final body)) => _awaitGap(body, child),
  TryStatement(:final body, :final finallyBlock) =>
    child == finallyBlock ? _awaitGap(body, child) : null,
  FunctionBody() => _isFutureCallbackBody(parent) ? _Gap.async : _Gap.none,
  _ => null,
};

/// The statements before [child] decide, or the walk goes on.
_Gap? _precedingGap(List<Statement> statements, AstNode child) {
  final gap = _scanPreceding(statements, child);
  return gap == _Gap.none ? null : gap;
}

/// [child] runs only after [condition] (an `if`/`?:` condition or the left
/// side of `&&`/`||`): a `mounted` check there guards it, an `await` is a gap.
_Gap? _conditionGap(Expression condition, AstNode child) {
  if (child == condition) return null;
  if (_mentionsMounted(condition)) return _Gap.guarded;
  return _awaitGap(condition, child);
}

/// [child] runs after [before]: an `await` in it is a gap.
_Gap? _awaitGap(AstNode before, AstNode child) =>
    child != before && _containsAwait(before) ? _Gap.async : null;

/// Whether [body] belongs to a closure passed to `Future.then`,
/// `whenComplete` or `catchError` (positionally or as `onError:`).
bool _isFutureCallbackBody(FunctionBody body) {
  final closure = body.parent;
  if (closure is! FunctionExpression) return false;
  var argument = closure.parent;
  if (argument is NamedArgument) argument = argument.parent;
  final invocation = argument?.parent;
  return argument is ArgumentList &&
      invocation is MethodInvocation &&
      _futureCallbacks.contains(invocation.methodName.name) &&
      _isFutureMethod(invocation.methodName.element);
}

class _MountedFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == 'mounted') found = true;
  }
}

class _AwaitFinder extends RecursiveAstVisitor<void> {
  bool found = false;

  @override
  void visitAwaitExpression(AwaitExpression node) {
    found = true;
  }

  @override
  void visitForStatement(ForStatement node) {
    if (node.awaitKeyword != null) found = true;
    super.visitForStatement(node);
  }

  @override
  void visitForElement(ForElement node) {
    if (node.awaitKeyword != null) found = true;
    super.visitForElement(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    // A closure's awaits run when the closure is called, not here.
  }
}

class _SetStateVisitor extends RecursiveAstVisitor<void> {
  _SetStateVisitor({required this.relativePath, required this.findings});

  final String relativePath;
  final List<Finding> findings;
  final AnchorCounter _anchors = AnchorCounter();

  @override
  void visitMethodInvocation(MethodInvocation node) {
    super.visitMethodInvocation(node);
    if (node.methodName.name != 'setState') return;
    final target = node.target;
    if (target != null &&
        target is! ThisExpression &&
        target is! SuperExpression) {
      return;
    }
    if (!_isFlutterStateSetState(node.methodName.element)) return;
    if (_gapBefore(node) == _Gap.async) _addFinding(node);
  }

  void _addFinding(MethodInvocation node) {
    final anchor = _anchors.next(
      '${enclosingMemberName(node)}:setState',
      normalizedSource(node),
    );
    final fingerprint = computeFingerprint(
      ruleId: SlopSetStateAfterAsyncGapRule.ruleIdStatic,
      relativePath: relativePath,
      semanticAnchor: anchor,
    );
    final lineInfo = (node.root as CompilationUnit).lineInfo;
    final location = lineInfo.getLocation(node.offset);

    findings.add(
      Finding(
        ruleId: SlopSetStateAfterAsyncGapRule.ruleIdStatic,
        severity: Severity.warning,
        filePath: relativePath,
        line: location.lineNumber,
        column: location.columnNumber,
        message:
            '`setState` runs after an async gap without a `mounted` check — '
            'if the screen was closed meanwhile, it throws.',
        fingerprint: fingerprint,
        kind: 'setstate-after-async-gap',
        remedy:
            'Check `mounted` right after the `await` (`if (!mounted) '
            'return;`) or wrap the call (`if (mounted) setState(…)`). If the '
            'state provably outlives the future, suppress with '
            '`// loam-ignore: slop-setstate-after-async-gap – <reason>`.',
      ),
    );
  }
}

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import 'complexity_metrics.dart';

export 'complexity_metrics.dart';

/// Calculates [ComplexityMetrics] for a single executable body.
///
/// Feed any [FunctionBody] — whether from a top-level function declaration,
/// method, constructor, getter, or setter — and receive a deterministic
/// [ComplexityMetrics] value.
///
/// **What is counted (Cyclomatic — basis 1):**
/// - `if` expression/statement: +1
/// - `for`/`for-in`/`for-each` statement: +1
/// - `while` statement: +1
/// - `do`…`while` statement: +1
/// - `case` clause (SwitchCase / SwitchPatternCase): +1 each
/// - `catch` clause: +1 each
/// - `&&` binary operator: +1
/// - `||` binary operator: +1
/// - `??` binary operator: +1
/// - `?:` conditional expression: +1
/// - `when` guard in a pattern (`GuardedPattern`): +1
///
/// `default` clauses, `else` branches, and `else-if` branches do NOT add
/// extra cyclomatic points (they represent the "else" path of an existing
/// decision already counted via the preceding `if`/`case`).
///
/// **What is counted (Cognitive — rules described in [ComplexityMetrics]):**
/// - Nesting-aware: `if`, `for`, `while`, `do`, `switch`, `catch` add
///   `1 + nestingDepth` and increase the nesting depth for their body.
/// - Flat +1: `??`, `?:`, `when` guard; logical-operator sequences (`&&`/`||`
///   — the first operator in a same-type run, or a switch of operator type,
///   adds +1; same-type continuation does not).
///
/// **Closures/local functions:**
/// Not enumerated as separate executables by this calculator. Their AST nodes
/// are traversed and their decision points contribute to the enclosing metric.
/// The `FunctionComplexityCollector` (Modul B) decides which executables to
/// enumerate; this calculator counts what is inside the body it receives.
///
/// **Determinism:**
/// The visitor is purely AST-structural, no state from outside the body is
/// read. Two invocations with equal AST inputs yield equal [ComplexityMetrics].
class ComplexityCalculator {
  /// Creates a [ComplexityCalculator].
  const ComplexityCalculator();

  /// Calculates [ComplexityMetrics] for the given [body].
  ///
  /// Returns `ComplexityMetrics(cyclomatic: 1, cognitive: 0)` for an empty or
  /// expression-body function with no decision points.
  ///
  /// If [body] is `null` (e.g. an abstract method with no body), returns the
  /// trivial result.
  ComplexityMetrics calculate(FunctionBody? body) {
    if (body == null || body is EmptyFunctionBody) {
      return const ComplexityMetrics(cyclomatic: 1, cognitive: 0);
    }
    final visitor = _ComplexityVisitor();
    body.accept(visitor);
    return ComplexityMetrics(
      cyclomatic: 1 + visitor._cyclomaticIncrement,
      cognitive: visitor._cognitiveScore,
    );
  }
}

// ---------------------------------------------------------------------------
// Internal visitor — not part of the public API.
// ---------------------------------------------------------------------------

/// Recursive AST visitor that accumulates cyclomatic and cognitive increments
/// for a single function body.
///
/// Nesting depth is managed with a simple integer counter: every structural
/// control-flow node (`if`, `for`, `while`, `do`, `switch`, `catch`) increments
/// the depth before visiting its body/consequent and decrements it afterwards.
///
/// Closures / local functions: when a [FunctionExpression] or
/// [FunctionDeclarationStatement] is encountered, the nesting depth is
/// temporarily reset to 0 so that the closure's own body is measured from
/// scratch. The closure's increments still flow into the same counters — the
/// depth reset only affects the nesting-multiplier, not the accumulation.
class _ComplexityVisitor extends RecursiveAstVisitor<void> {
  int _cyclomaticIncrement = 0;
  int _cognitiveScore = 0;
  int _nestingDepth = 0;

  // ---- Nesting-depth helpers -----------------------------------------------

  void _enterNested() => _nestingDepth++;
  void _exitNested() => _nestingDepth--;

  void _addNested() {
    _cognitiveScore += 1 + _nestingDepth;
  }

  // ---- Control-flow nodes --------------------------------------------------

  // Tracks whether the current if-chain is a continuation (else-if) so that
  // `visitIfStatement` knows not to add another `_addNested` increment.
  bool _ifIsContinuation = false;

  @override
  void visitIfStatement(IfStatement node) {
    _cyclomaticIncrement++;

    if (_ifIsContinuation) {
      // `else if` continuation: flat +1 only (no nesting multiplier).
      _cognitiveScore++;
      _ifIsContinuation = false;
    } else {
      // New `if`: nesting-aware increment.
      _addNested();
    }

    // Visit the condition at the current depth (before entering body).
    node.expression.accept(this);

    _enterNested();
    node.thenStatement.accept(this);
    _exitNested();

    final elseStatement = node.elseStatement;
    if (elseStatement != null) {
      if (elseStatement is IfStatement) {
        // `else if`: mark as continuation before visiting — prevents double-
        // counting of `_addNested` in the recursive call.
        _ifIsContinuation = true;
        elseStatement.accept(this);
        _ifIsContinuation = false; // reset in case it was not consumed
      } else {
        // plain `else`: flat +1, then visit body at depth+1
        _cognitiveScore++;
        _enterNested();
        elseStatement.accept(this);
        _exitNested();
      }
    }
    // Do NOT call super.visitIfStatement — children were handled manually.
  }

  @override
  void visitForStatement(ForStatement node) {
    _cyclomaticIncrement++;
    _addNested();
    _enterNested();
    super.visitForStatement(node);
    _exitNested();
  }

  @override
  void visitWhileStatement(WhileStatement node) {
    _cyclomaticIncrement++;
    _addNested();
    _enterNested();
    super.visitWhileStatement(node);
    _exitNested();
  }

  @override
  void visitDoStatement(DoStatement node) {
    _cyclomaticIncrement++;
    _addNested();
    _enterNested();
    super.visitDoStatement(node);
    _exitNested();
  }

  @override
  void visitSwitchStatement(SwitchStatement node) {
    // The switch itself adds a nesting-aware cognitive point.
    _addNested();
    _enterNested();
    // Visit members to count each case; cyclomatic is handled per case below.
    super.visitSwitchStatement(node);
    _exitNested();
  }

  @override
  void visitSwitchCase(SwitchCase node) {
    _cyclomaticIncrement++;
    // No extra cognitive point for individual case labels — the switch itself
    // already added the nesting-aware increment.
    super.visitSwitchCase(node);
  }

  @override
  void visitSwitchPatternCase(SwitchPatternCase node) {
    _cyclomaticIncrement++;
    super.visitSwitchPatternCase(node);
  }

  // `SwitchDefault` — does NOT add a cyclomatic point (it is the catch-all
  // "else" path). Visited normally by the super call in visitSwitchStatement.

  @override
  void visitTryStatement(TryStatement node) {
    // `try` itself is not a decision point; each `catch` clause is.
    super.visitTryStatement(node);
  }

  @override
  void visitCatchClause(CatchClause node) {
    _cyclomaticIncrement++;
    _addNested();
    _enterNested();
    super.visitCatchClause(node);
    _exitNested();
  }

  // ---- Boolean/null operators ----------------------------------------------

  @override
  void visitBinaryExpression(BinaryExpression node) {
    final op = node.operator.type;
    if (op == TokenType.AMPERSAND_AMPERSAND ||
        op == TokenType.BAR_BAR ||
        op == TokenType.QUESTION_QUESTION) {
      _cyclomaticIncrement++;

      if (op == TokenType.QUESTION_QUESTION) {
        // `??` always counts as flat +1.
        _cognitiveScore++;
      } else {
        // Logical operator (`&&` / `||`): flat +1 only when this operator
        // differs from the *parent* logical operator (or the parent is not a
        // logical operator). This models "sequence of same operators = one
        // penalty; switching = new penalty".
        if (!_isContinuationOfSameLogicalOp(node)) {
          _cognitiveScore++;
        }
      }
    }
    super.visitBinaryExpression(node);
  }

  /// Returns `true` when [node] is the LEFT operand of a [BinaryExpression]
  /// with the same logical operator — meaning the outer node already represents
  /// this run and this node is a continuation (do not count again).
  ///
  /// Example: `a && b && c` parses as `(a && b) && c`.
  /// - Outer `&&`: not a left-child of same-type parent → counts (+1).
  /// - Inner `&&` (`a && b`): IS the left operand of the outer `&&` with the
  ///   same operator → continuation → does NOT count.
  bool _isContinuationOfSameLogicalOp(BinaryExpression node) {
    final parent = node.parent;
    if (parent is BinaryExpression) {
      return parent.operator.type == node.operator.type &&
          parent.leftOperand == node;
    }
    return false;
  }

  // ---- Conditional expression ----------------------------------------------

  @override
  void visitConditionalExpression(ConditionalExpression node) {
    _cyclomaticIncrement++;
    _cognitiveScore++; // flat +1
    super.visitConditionalExpression(node);
  }

  // ---- Pattern guard -------------------------------------------------------

  @override
  void visitGuardedPattern(GuardedPattern node) {
    // `when` guard — both cyclomatic and cognitive flat +1.
    if (node.whenClause != null) {
      _cyclomaticIncrement++;
      _cognitiveScore++;
    }
    super.visitGuardedPattern(node);
  }

  // ---- Closures / local functions ------------------------------------------
  //
  // When encountering a nested closure or local function the nesting depth is
  // temporarily reset to 0. This ensures that the closure's own structure is
  // measured from scratch (not carrying the enclosing depth), while the
  // accumulated counts still flow into the same counters (the closure's
  // complexity is part of the enclosing executable's metric).

  @override
  void visitFunctionExpression(FunctionExpression node) {
    final savedDepth = _nestingDepth;
    _nestingDepth = 0;
    super.visitFunctionExpression(node);
    _nestingDepth = savedDepth;
  }

  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    final savedDepth = _nestingDepth;
    _nestingDepth = 0;
    super.visitFunctionDeclarationStatement(node);
    _nestingDepth = savedDepth;
  }
}

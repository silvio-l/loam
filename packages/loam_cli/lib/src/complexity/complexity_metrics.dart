/// An immutable value object holding the complexity metrics of a single
/// executable (function, method, constructor, getter, or setter).
///
/// Instances are produced by [ComplexityCalculator].
///
/// Equality is value-based: two [ComplexityMetrics] are equal when both
/// [cyclomatic] and [cognitive] match.
final class ComplexityMetrics {
  /// Creates a [ComplexityMetrics] with the given [cyclomatic] and [cognitive]
  /// values.
  const ComplexityMetrics({required this.cyclomatic, required this.cognitive});

  /// The cyclomatic complexity of the executable (McCabe, 1976).
  ///
  /// Basis: 1. Each of the following decision points adds 1:
  /// - `if` expression or statement (the condition counts once, regardless of
  ///   `else`)
  /// - `for` statement (traditional `for`, `for-in`, `for-each`)
  /// - `while` statement
  /// - `do`…`while` statement
  /// - `case` clause in a `switch` statement (one per `SwitchCase` or
  ///   `SwitchPatternCase` with a body; `default` does NOT add a point because
  ///   it is the "else" path)
  /// - `catch` clause in a `try` statement (one per catch arm)
  /// - `&&` (logical-and binary operator)
  /// - `||` (logical-or binary operator)
  /// - `??` (null-coalescing binary operator)
  /// - `?:` conditional expression
  /// - `when` guard in a pattern (`GuardedPattern.whenClause`)
  ///
  /// Closures/local functions nested inside the executable are NOT counted as
  /// separate executables; their decision points contribute to the enclosing
  /// executable's count.
  final int cyclomatic;

  /// The cognitive complexity of the executable.
  ///
  /// Inspired by the Cognitive Complexity metric (Campagne, 2018) but adapted
  /// for reproducibility and conservative defaults:
  ///
  /// **Increment rules (nesting-aware):**
  /// Each of the following structural elements adds `1 + nestingDepth` where
  /// [nestingDepth] is the number of nesting-control-flow levels already active
  /// at the point where the element is encountered:
  /// - `if` / `else if` / `else` (each branch adds independently at its depth)
  /// - `for` / `while` / `do` loops
  /// - `switch` statement
  /// - `catch` clause
  ///
  /// **Flat increments (no nesting multiplier):**
  /// The following add exactly 1 regardless of nesting depth:
  /// - Each logical operator sequence break: a `&&` or `||` sequence is
  ///   treated as a single flat +1 for the *first* operator in a consecutive
  ///   run of the same type; switching operator type within the same expression
  ///   adds another +1. In practice: count the number of `&&` and `||` tokens
  ///   where the operator differs from the immediately preceding logical op.
  /// - `??` (null-coalescing) — flat +1 each occurrence.
  /// - `?:` conditional expression — flat +1 each occurrence.
  /// - `when` guard in a pattern — flat +1 each occurrence.
  ///
  /// **Nesting-depth tracking:**
  /// Depth increments are scoped to `if`, `for`, `while`, `do`, `switch`, and
  /// `catch` bodies. Closures/local functions reset the depth to 0 internally
  /// (their complexity flows into the enclosing metric but they do not carry
  /// the enclosing nesting depth into their own body).
  ///
  /// **Trivial executables:**
  /// An empty or expression-body executable with no decision points has
  /// `cognitive == 0`.
  final int cognitive;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ComplexityMetrics &&
          other.cyclomatic == cyclomatic &&
          other.cognitive == cognitive;

  @override
  int get hashCode => Object.hash(cyclomatic, cognitive);

  @override
  String toString() =>
      'ComplexityMetrics(cyclomatic: $cyclomatic, '
      'cognitive: $cognitive)';
}

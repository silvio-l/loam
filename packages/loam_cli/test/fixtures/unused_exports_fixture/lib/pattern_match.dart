/// Fixture for object-pattern destructuring reads (HellerIO Dart-3 pattern gap).
///
/// `patternRead` is consumed ONLY through `case PatternHost(:final patternRead)`
/// in pattern_consumer.dart — there is no `.patternRead` SimpleIdentifier read
/// anywhere. It must NOT be reported as unused.
///
/// `neverDestructured` is never read in any form — it MUST be reported, proving
/// the pattern handling does not blanket-suppress the whole class.
library;

/// Host class destructured via an object pattern.
class PatternHost {
  const PatternHost(this.patternRead, this.neverDestructured);

  /// Read exclusively via `case PatternHost(:final patternRead)` — NOT reported.
  final String patternRead;

  /// Never read in any form — REPORTED as unused.
  final String neverDestructured;
}

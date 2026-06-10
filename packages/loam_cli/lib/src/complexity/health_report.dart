import 'function_complexity.dart';

/// An immutable value object representing the aggregated health of a Dart
/// package's executable complexity distribution.
///
/// Produced by [HealthScore.compute]. Equality is value-based on all three
/// fields.
///
/// ### Score formula (see [HealthScore] for full documentation)
///
/// `score` is an integer in [0, 100]. Higher is healthier.
///
/// ### Grade bands
///
/// | Grade | Score range |
/// |-------|------------|
/// | A     | 90–100     |
/// | B     | 75–89      |
/// | C     | 60–74      |
/// | D     | 45–59      |
/// | F     | 0–44       |
///
/// ### Hotspots
///
/// The [hotspots] list contains the most complex executables from the entire
/// distribution (not just rule-threshold breaches), sorted descending by
/// *complexity magnitude* (`max(cyclomatic, cognitive)`), with a
/// deterministic tie-break on `filePath` → `line` → `qualifiedName`, capped
/// at [HealthScore.topN] entries.
final class HealthReport {
  /// Creates a [HealthReport].
  ///
  /// [hotspots] is wrapped in [List.unmodifiable] so callers cannot mutate the
  /// list in place, preserving the immutable-value-object contract.
  HealthReport({
    required this.score,
    required this.grade,
    required List<FunctionComplexity> hotspots,
  }) : assert(score >= 0 && score <= 100, 'score must be in [0, 100]'),
       hotspots = List.unmodifiable(hotspots);

  /// The health score in [0, 100]. 100 means a perfectly clean distribution;
  /// 0 means the worst possible distribution.
  final int score;

  /// The letter grade derived from [score]. One of `A`, `B`, `C`, `D`, `F`.
  final String grade;

  /// The most complex executables in the distribution, sorted descending by
  /// complexity magnitude. At most [HealthScore.topN] entries.
  final List<FunctionComplexity> hotspots;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HealthReport &&
          other.score == score &&
          other.grade == grade &&
          _listEquals(other.hotspots, hotspots);

  @override
  int get hashCode => Object.hash(score, grade, Object.hashAll(hotspots));

  @override
  String toString() =>
      'HealthReport(score: $score, grade: $grade, '
      'hotspots: [${hotspots.length} items])';

  static bool _listEquals(
    List<FunctionComplexity> a,
    List<FunctionComplexity> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

import 'function_complexity.dart';

/// An immutable value object representing the aggregated health of a Dart
/// package — a composite of its **finding load** (bugs/slop/a11y issues) and
/// its **complexity distribution** (cyclomatic/cognitive hotspots).
///
/// Produced by [HealthScore.compute]. Equality is value-based on all fields.
///
/// ### Score formula (see [HealthScore] for full documentation)
///
/// `score` is an integer in [0, 100], combining [findingsContribution] and
/// [complexityContribution]. Higher is healthier.
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
    required this.findingsContribution,
    required this.complexityContribution,
  }) : assert(score >= 0 && score <= 100, 'score must be in [0, 100]'),
       assert(
         findingsContribution >= 0 && findingsContribution <= 100,
         'findingsContribution must be in [0, 100]',
       ),
       assert(
         complexityContribution >= 0 && complexityContribution <= 100,
         'complexityContribution must be in [0, 100]',
       ),
       hotspots = List.unmodifiable(hotspots);

  /// The composite health score in [0, 100]. 100 means no findings and a
  /// perfectly clean complexity distribution; 0 means the worst possible
  /// combination of both.
  final int score;

  /// The letter grade derived from [score]. One of `A`, `B`, `C`, `D`, `F`.
  final String grade;

  /// The findings-axis sub-score in [0, 100] — how healthy the project looks
  /// purely from its weighted, size-normalised finding load. 100 means no
  /// findings; 0 means the finding density is at or above the saturation
  /// threshold. See [HealthScore] for the exact formula.
  final int findingsContribution;

  /// The complexity-axis sub-score in [0, 100] — how healthy the project
  /// looks purely from its cyclomatic/cognitive hotspot distribution.
  /// Hotspots are weighed absolutely, not diluted by the total function
  /// count. See [HealthScore] for the exact formula.
  final int complexityContribution;

  /// The most complex executables in the distribution, sorted descending by
  /// complexity magnitude. At most [HealthScore.topN] entries.
  final List<FunctionComplexity> hotspots;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HealthReport &&
          other.score == score &&
          other.grade == grade &&
          other.findingsContribution == findingsContribution &&
          other.complexityContribution == complexityContribution &&
          _listEquals(other.hotspots, hotspots);

  @override
  int get hashCode => Object.hash(
    score,
    grade,
    findingsContribution,
    complexityContribution,
    Object.hashAll(hotspots),
  );

  @override
  String toString() =>
      'HealthReport(score: $score, grade: $grade, '
      'findingsContribution: $findingsContribution, '
      'complexityContribution: $complexityContribution, '
      'hotspots: [${hotspots.length} items])';

  static bool _listEquals(
    List<FunctionComplexity> a,
    List<FunctionComplexity> b,
    // loam-ignore: code-duplicates – per-class equality helper; extracting a shared generic would require a new dependency and obscure the type specificity.
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

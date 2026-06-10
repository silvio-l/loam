import 'function_complexity.dart';
import 'health_report.dart';

export 'health_report.dart';

/// Aggregates a list of [FunctionComplexity] measurements into a single
/// [HealthReport] containing a score, grade, and hotspot list.
///
/// ---
///
/// ## Score formula
///
/// The score is derived from the *penalty ratio* of the distribution:
///
/// 1. **Complexity magnitude** of each executable is defined as
///    `max(cyclomatic, cognitive)`. This captures whichever dimension is
///    dominant for a given function without arbitrarily double-penalising.
///
/// 2. **Threshold:** executables with magnitude > [_penaltyThreshold] (= 10)
///    are "heavy". This is intentionally conservative; only genuinely
///    non-trivial functions contribute to the penalty.
///
/// 3. **Weighted penalty per heavy executable:**
///    `penalty = magnitude - _penaltyThreshold`
///    i.e. the amount by which it exceeds the threshold.
///    A function at 11 contributes 1; a function at 20 contributes 10.
///
/// 4. **Total penalty** = sum of all individual penalties.
///
/// 5. **Normalisation:** the worst-case penalty for a list of N executables is
///    assumed to be `N × _worstCasePenaltyPerFunction` (= `N × 40`). This
///    means: if every executable had magnitude 50 (40 over threshold), the
///    normalised penalty would be 1.0 — a score of 0.
///    When the list is empty, there is no penalty and the score is 100.
///
/// 6. **Score = clamp(round(100 × (1 − normalisedPenalty)), 0, 100)**.
///
/// ### Example
///
/// 10 executables, all with magnitude ≤ 10:
/// - totalPenalty = 0, score = 100.
///
/// 10 executables, one with magnitude 15 (penalty 5), rest ≤ 10:
/// - totalPenalty = 5, worstCase = 10 × 40 = 400
/// - normalisedPenalty = 5 / 400 = 0.0125
/// - score = round(100 × 0.9875) = 99.
///
/// ---
///
/// ## Grade bands
///
/// | Grade | Score range |
/// |-------|------------|
/// | A     | 90–100     |
/// | B     | 75–89      |
/// | C     | 60–74      |
/// | D     | 45–59      |
/// | F     | 0–44       |
///
/// ---
///
/// ## Hotspot list
///
/// The [HealthReport.hotspots] list contains the top [topN] (= 20) executables
/// by complexity magnitude, sorted **descending**. Tie-break order:
/// `filePath` ascending → `line` ascending → `qualifiedName` ascending.
/// This is applied to the **whole distribution**, not just rule-threshold
/// breaches.
///
/// ---
///
/// This module is a **pure aggregation module**. It has no dependency on
/// `Reporter`, `ReportPayload`, or `Finding`. The split-architecture rationale
/// is documented in the PRD (Modul D): the health score is a distribution view
/// that does not fit Finding form and intentionally stays outside the gate
/// pipeline.
class HealthScore {
  /// Creates a [HealthScore] engine.
  const HealthScore();

  // ---------------------------------------------------------------------------
  // Documented constants
  // ---------------------------------------------------------------------------

  /// The complexity magnitude threshold above which an executable is
  /// considered "heavy" and contributes a penalty to the score.
  ///
  /// Chosen conservatively (10) to avoid penalising moderately complex but
  /// reasonable functions and to limit false-positive pressure.
  static const int penaltyThreshold = 10;

  /// The assumed worst-case per-executable penalty used for normalisation.
  ///
  /// A function with magnitude `penaltyThreshold + worstCasePenaltyPerFunction`
  /// (i.e. magnitude = 50) contributes the maximum single-function penalty.
  /// Magnitudes above 50 are still clamped at this value for normalisation
  /// purposes so that a single extreme outlier cannot collapse the whole score
  /// to 0 on its own.
  static const int worstCasePenaltyPerFunction = 40;

  /// Maximum number of hotspots returned in [HealthReport.hotspots].
  ///
  /// The hotspot list shows the top N executables by complexity magnitude,
  /// independent of rule thresholds, capped here to keep output readable.
  static const int topN = 20;

  // ---------------------------------------------------------------------------
  // Grade bands (inclusive lower bound, exclusive upper bound except A)
  // ---------------------------------------------------------------------------

  /// Maps a [score] in [0, 100] to a letter grade.
  ///
  /// | Grade | Score range |
  /// |-------|------------|
  /// | A     | 90–100     |
  /// | B     | 75–89      |
  /// | C     | 60–74      |
  /// | D     | 45–59      |
  /// | F     | 0–44       |
  static String gradeFor(int score) {
    if (score >= 90) return 'A';
    if (score >= 75) return 'B';
    if (score >= 60) return 'C';
    if (score >= 45) return 'D';
    return 'F';
  }

  // ---------------------------------------------------------------------------
  // Core computation
  // ---------------------------------------------------------------------------

  /// Aggregates [functions] into a [HealthReport].
  ///
  /// The computation is deterministic: two calls with equal [functions] lists
  /// (same elements in same order) always return equal [HealthReport]s.
  ///
  /// [functions] need not be pre-sorted; this method sorts internally for both
  /// penalty accumulation and hotspot extraction.
  ///
  /// An empty [functions] list returns score 100 / grade A / empty hotspots.
  HealthReport compute(List<FunctionComplexity> functions) {
    if (functions.isEmpty) {
      return HealthReport(score: 100, grade: 'A', hotspots: []);
    }

    final n = functions.length;

    // 1. Compute per-executable magnitude and accumulate total penalty.
    int totalPenalty = 0;
    for (final f in functions) {
      final magnitude = _magnitude(f);
      if (magnitude > penaltyThreshold) {
        final raw = magnitude - penaltyThreshold;
        // Clamp individual contribution so a single extreme outlier cannot
        // dominate the normalised penalty beyond its fair share.
        totalPenalty += raw < worstCasePenaltyPerFunction
            ? raw
            : worstCasePenaltyPerFunction;
      }
    }

    // 2. Normalise against worst-case total penalty.
    final worstCase = n * worstCasePenaltyPerFunction;
    final normalisedPenalty = totalPenalty / worstCase;

    // 3. Score: 100 × (1 − normalisedPenalty), rounded, clamped to [0, 100].
    final raw = (100.0 * (1.0 - normalisedPenalty)).round();
    final score = raw.clamp(0, 100);

    // 4. Grade.
    final grade = gradeFor(score);

    // 5. Hotspots: whole distribution sorted descending by magnitude,
    //    deterministic tie-break: filePath asc → line asc → qualifiedName asc,
    //    capped at topN.
    final sorted = List<FunctionComplexity>.of(functions)
      ..sort(_hotspotComparator);
    final hotspots = sorted.length > topN ? sorted.sublist(0, topN) : sorted;

    return HealthReport(score: score, grade: grade, hotspots: hotspots);
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Complexity magnitude for a single executable.
  ///
  /// Defined as `max(cyclomatic, cognitive)`. Using the maximum captures
  /// whichever dimension is dominant without double-penalising.
  static int _magnitude(FunctionComplexity f) {
    final c = f.metrics.cyclomatic;
    final g = f.metrics.cognitive;
    return c > g ? c : g;
  }

  /// Comparator for the hotspot list: descending magnitude,
  /// then ascending filePath → line → qualifiedName.
  static int _hotspotComparator(FunctionComplexity a, FunctionComplexity b) {
    final magA = _magnitude(a);
    final magB = _magnitude(b);
    // Descending by magnitude.
    final magCmp = magB.compareTo(magA);
    if (magCmp != 0) return magCmp;
    // Tie-break: ascending filePath.
    final pathCmp = a.filePath.compareTo(b.filePath);
    if (pathCmp != 0) return pathCmp;
    // Tie-break: ascending line.
    final lineCmp = a.line.compareTo(b.line);
    if (lineCmp != 0) return lineCmp;
    // Tie-break: ascending qualifiedName.
    return a.qualifiedName.compareTo(b.qualifiedName);
  }
}

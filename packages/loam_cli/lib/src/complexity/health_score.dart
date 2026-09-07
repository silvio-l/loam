import '../model/finding.dart';
import 'function_complexity.dart';
import 'health_report.dart';

export 'health_report.dart';

/// Aggregates a list of [FunctionComplexity] measurements together with the
/// project's [Finding]s and size into a single composite [HealthReport]
/// containing a score, grade, contribution breakdown, and hotspot list.
///
/// ---
///
/// ## Why a composite score
///
/// The score used to measure *only* the complexity distribution. That let a
/// repo with 150+ findings (bugs, slop, a11y violations) still show a
/// near-perfect score, because complexity says nothing about finding load.
/// The composite score fixes this: it combines a **findings axis** (weighted,
/// size-normalised finding density) with the existing **complexity axis**
/// (hotspot severity, now weighed absolutely instead of averaged across every
/// function in the project) and lets substantial finding load impose a hard
/// ceiling on the grade.
///
/// ---
///
/// ## Findings axis
///
/// 1. **Severity weight:** each [Finding] contributes
///    [severityWeightError] (error), [severityWeightWarning] (warning), or
///    [severityWeightInfo] (info) — error counts more than warning, warning
///    more than info.
/// 2. **Weighted load** = sum of severity weights across all findings.
/// 3. **Size normalisation:** weighted load is expressed as a *density* —
///    weighted load per [sizeNormalizationLines] (= 1000) lines of
///    `linesAnalyzed`. A `linesAnalyzed` of 0 or less is treated as one unit
///    (1000 lines) so the density stays finite for tiny/unknown-size inputs.
///    `density = weightedLoad / max(linesAnalyzed, 1) × 1000`.
/// 4. **Findings sub-score:** `findingsContribution = round(100 × (1 −
///    min(density / findingsSaturationDensity, 1)))`. At density 0 the
///    sub-score is 100; at density ≥ [findingsSaturationDensity] (= 40) it
///    bottoms out at 0.
/// 5. **Hard ceiling:** once `density` reaches [substantialDensityThreshold]
///    (= 5), the finding load is considered "substantial" and the *final
///    composite score* is capped at [hardCapScore] (= 89) — one point below
///    the Grade A threshold — no matter how clean the complexity axis is.
///    This is what makes the 150+-findings case (the motivating regression
///    for this ticket) fall out of Grade A, and it also catches lighter-but-
///    still-substantial finding loads that the weighted combination alone
///    would not yet have pushed under 90 — see "Combined examples" below.
///
/// ### Findings axis examples
///
/// | Findings (severity mix)  | linesAnalyzed | weightedLoad | density | findingsContribution |
/// |----------------------------|---------------|--------------|---------|-----------------------|
/// | none                        | any           | 0            | 0.0     | 100                   |
/// | 10 warning                  | 10,000        | 20           | 2.0     | 95                    |
/// | 150 warning                 | 15,000        | 300          | 20.0    | 50                    |
/// | 150 warning                 | 150,000       | 300          | 2.0     | 95                    |
/// | 20 error                    | 5,000         | 100          | 20.0    | 50                    |
///
/// The third and fourth rows are the same finding count with different
/// project sizes: the smaller project is much denser, so its sub-score is
/// much lower — this is the size-normalisation requirement.
///
/// ---
///
/// ## Complexity axis
///
/// Unchanged per-executable model, but **no longer averaged across every
/// function in the project** — a handful of brutal hotspots in a 5,000-
/// function repo used to be diluted away by the `N`-based normalisation; now
/// they are weighed against a fixed budget instead.
///
/// 1. **Complexity magnitude** of each executable is `max(cyclomatic,
///    cognitive)`.
/// 2. **Threshold:** magnitude > [penaltyThreshold] (= 10) is "heavy".
/// 3. **Per-executable penalty:** `min(magnitude − penaltyThreshold,
///    worstCasePenaltyPerFunction)` (= capped at 40) — a single outlier can't
///    dominate the sum on its own.
/// 4. **Total penalty** = sum of all individual penalties.
/// 5. **Fixed normalisation:** `complexityContribution = round(100 × (1 −
///    min(totalPenalty / hotspotWorstCaseTotalPenalty, 1)))`, where
///    [hotspotWorstCaseTotalPenalty] (= 200) is a fixed budget — equivalent
///    to 5 maximally-heavy functions — **independent of how many functions
///    the project has**.
///
/// ### Complexity axis examples
///
/// | Functions                                              | totalPenalty | complexityContribution |
/// |----------------------------------------------------------|--------------|-------------------------|
/// | 5,000 trivial functions                                   | 0            | 100                     |
/// | 5,000 functions, 3 with magnitude 50 (penalty 40 each)    | 120          | 40                      |
/// | 10 functions, 1 with magnitude 50 (penalty 40)             | 40           | 80                      |
///
/// The middle row is the point of the change: 3 brutal hotspots in a huge
/// repo used to normalise away to a near-perfect score (`3×40 / 5000×40 ≈
/// 0`); now they cost 60 points off the complexity axis regardless of `N`.
///
/// ---
///
/// ## Combining the axes
///
/// `score = round([findingsWeight] × findingsContribution +
/// [complexityWeight] × complexityContribution)`, then the hard ceiling from
/// the findings axis (if triggered) is applied, then the result is clamped to
/// `[0, 100]`.
///
/// [findingsWeight] (= 0.6) and [complexityWeight] (= 0.4) make finding load
/// the primary driver — a project riddled with findings should not be able to
/// buy back Grade A with a spotless complexity distribution.
///
/// ### Combined examples
///
/// | Scenario                                                        | findingsContribution | complexityContribution | hard cap? | score | grade |
/// |--------------------------------------------------------------------|-----------------------|--------------------------|-----------|-------|-------|
/// | Clean, tiny project, no findings                                    | 100                   | 100                      | no        | 100   | A     |
/// | 150 findings (mixed error/warning), 20 near-trivial fns, 15k lines   | 25                    | 100                      | yes (→89, no effect — already below) | 55 | D |
/// | Few brutal hotspots (3 of ~500 fns), huge repo, no findings          | 100                   | 40                       | no        | 76    | B     |
/// | Moderate finding density (25 errors, 20k lines), perfect complexity  | 84                    | 100                      | yes (→89, DOES lower the score) | 89 | B |
///
/// The last row is the case that motivates a *separate* hard cap on top of
/// the weighted combination: at that density the weighted formula alone
/// would still land at 90 (Grade A) — `round(0.6×84 + 0.4×100) = 90` — but
/// the hard cap forces it down to 89 (Grade B) because the finding load is
/// already substantial.
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
/// `Reporter` or `ReportPayload` — its only model-layer dependency is
/// [Finding] itself, which it consumes as plain input data (severity counts),
/// never re-exporting reporter concerns. The split-architecture rationale is
/// documented in the PRD (Modul D): the health score is a distribution view
/// that does not fit Finding form and intentionally stays outside the gate
/// pipeline.
class HealthScore {
  /// Creates a [HealthScore] engine.
  const HealthScore();

  // ---------------------------------------------------------------------------
  // Documented constants — complexity axis
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

  /// The fixed penalty budget the complexity axis is normalised against.
  ///
  /// Deliberately **not** a function of the project's total executable count
  /// — a handful of brutal hotspots must cost the same regardless of how many
  /// trivial functions surround them (see class doc, "Complexity axis"). Set
  /// to 200 — equivalent to 5 functions each at the maximum per-function
  /// penalty of 40.
  static const int hotspotWorstCaseTotalPenalty = 200;

  /// Maximum number of hotspots returned in [HealthReport.hotspots].
  ///
  /// The hotspot list shows the top N executables by complexity magnitude,
  /// independent of rule thresholds, capped here to keep output readable.
  static const int topN = 20;

  // ---------------------------------------------------------------------------
  // Documented constants — findings axis
  // ---------------------------------------------------------------------------

  /// Severity weight for [Severity.error] findings — highest weight.
  static const int severityWeightError = 5;

  /// Severity weight for [Severity.warning] findings.
  static const int severityWeightWarning = 2;

  /// Severity weight for [Severity.info] findings — lowest weight.
  static const int severityWeightInfo = 1;

  /// The line count used as the unit for finding-density normalisation.
  ///
  /// Density is expressed as "weighted finding load per
  /// [sizeNormalizationLines] lines" so the same absolute finding count reads
  /// as worse in a small project than in a large one.
  static const int sizeNormalizationLines = 1000;

  /// The finding density (weighted load per [sizeNormalizationLines] lines)
  /// at which the findings sub-score bottoms out at 0.
  static const double findingsSaturationDensity = 40;

  /// The finding density at or above which finding load is considered
  /// "substantial" and the final composite score is hard-capped at
  /// [hardCapScore], regardless of the complexity axis.
  ///
  /// Set below the density at which the weighted combination alone would
  /// already drop the score under 90 (≈6.7, given [findingsWeight] and
  /// [complexityWeight]) — otherwise the cap would never actually bind. At
  /// density 5 with a perfect complexity axis, the weighted combination alone
  /// still reaches ~93 (Grade A); the hard cap is what forces it to
  /// [hardCapScore] instead. See "Combined examples" below.
  static const double substantialDensityThreshold = 5;

  /// The composite score ceiling applied when finding density reaches
  /// [substantialDensityThreshold]. One point below the Grade A threshold
  /// (90), so substantial finding load can never buy back Grade A.
  static const int hardCapScore = 89;

  // ---------------------------------------------------------------------------
  // Documented constants — combination weights
  // ---------------------------------------------------------------------------

  /// Weight of [HealthReport.findingsContribution] in the composite [score].
  ///
  /// Findings are weighted more heavily than complexity (0.6 vs 0.4) so that
  /// finding load is the primary driver of the score — this is the direct
  /// fix for the "150+ findings still scores 99" symptom.
  static const double findingsWeight = 0.6;

  /// Weight of [HealthReport.complexityContribution] in the composite
  /// [score].
  static const double complexityWeight = 0.4;

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

  /// Aggregates [functions], [findings], and [linesAnalyzed] into a
  /// [HealthReport].
  ///
  /// The computation is deterministic: two calls with equal arguments (same
  /// elements in same order) always return equal [HealthReport]s — the
  /// underlying sums are commutative, so element order never affects the
  /// result (Invariant 5).
  ///
  /// [functions] need not be pre-sorted; this method sorts internally for both
  /// penalty accumulation and hotspot extraction. [findings] need not be
  /// sorted either — only severity counts matter.
  ///
  /// An empty [functions] list and empty [findings] list returns score 100 /
  /// grade A / empty hotspots, regardless of [linesAnalyzed].
  HealthReport compute(
    List<FunctionComplexity> functions, {
    required List<Finding> findings,
    required int linesAnalyzed,
  }) {
    // -----------------------------------------------------------------------
    // Findings axis.
    // -----------------------------------------------------------------------
    var weightedLoad = 0;
    for (final f in findings) {
      weightedLoad += switch (f.severity) {
        Severity.error => severityWeightError,
        Severity.warning => severityWeightWarning,
        Severity.info => severityWeightInfo,
      };
    }

    // Guard against division by zero / negative sizes: treat as one
    // normalisation unit (sizeNormalizationLines) so density stays finite.
    final sizeLines = linesAnalyzed > 0
        ? linesAnalyzed
        : sizeNormalizationLines;
    final density = weightedLoad / sizeLines * sizeNormalizationLines;

    final findingsPenaltyRatio = (density / findingsSaturationDensity).clamp(
      0.0,
      1.0,
    );
    final findingsContribution = (100.0 * (1.0 - findingsPenaltyRatio))
        .round()
        .clamp(0, 100);

    final substantialFindingLoad = density >= substantialDensityThreshold;

    // -----------------------------------------------------------------------
    // Complexity axis.
    // -----------------------------------------------------------------------
    var totalPenalty = 0;
    for (final f in functions) {
      final magnitude = _magnitude(f);
      if (magnitude > penaltyThreshold) {
        final raw = magnitude - penaltyThreshold;
        // Clamp individual contribution so a single extreme outlier cannot
        // dominate the fixed budget beyond its fair share.
        totalPenalty += raw < worstCasePenaltyPerFunction
            ? raw
            : worstCasePenaltyPerFunction;
      }
    }

    // Fixed budget, NOT scaled by the number of functions — a handful of
    // brutal hotspots must cost the same regardless of project size.
    final complexityPenaltyRatio = (totalPenalty / hotspotWorstCaseTotalPenalty)
        .clamp(0.0, 1.0);
    final complexityContribution = (100.0 * (1.0 - complexityPenaltyRatio))
        .round()
        .clamp(0, 100);

    // -----------------------------------------------------------------------
    // Combination.
    // -----------------------------------------------------------------------
    final combined =
        (findingsWeight * findingsContribution +
                complexityWeight * complexityContribution)
            .round();
    var score = combined.clamp(0, 100);
    if (substantialFindingLoad && score > hardCapScore) {
      score = hardCapScore;
    }

    final grade = gradeFor(score);

    // -----------------------------------------------------------------------
    // Hotspots: whole distribution sorted descending by magnitude,
    // deterministic tie-break: filePath asc → line asc → qualifiedName asc,
    // capped at topN.
    // -----------------------------------------------------------------------
    final sorted = List<FunctionComplexity>.of(functions)
      ..sort(_hotspotComparator);
    final hotspots = sorted.length > topN ? sorted.sublist(0, topN) : sorted;

    return HealthReport(
      score: score,
      grade: grade,
      hotspots: hotspots,
      findingsContribution: findingsContribution,
      complexityContribution: complexityContribution,
    );
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

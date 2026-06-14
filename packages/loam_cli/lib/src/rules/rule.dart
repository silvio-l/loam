import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/rule_category.dart';
export '../model/rule_category.dart';

/// The plugin contract for every loam.dev analysis capability.
///
/// A [Rule] receives the fully resolved project ([ProjectLoadResult]) and
/// returns zero or more [Finding]s. It has no knowledge of severity thresholds,
/// baselines, or output formatting — those concerns belong to the gate and
/// reporter layers.
///
/// Implementations must:
/// - provide a stable [ruleId] in kebab-case (e.g. `unused-public-exports`).
/// - declare the high-level [category] this rule belongs to.
/// - be deterministic: identical inputs must produce identical outputs
///   (Invariant 4 — reproducibility).
/// - compute each [Finding.fingerprint] via [computeFingerprint] so that
///   fingerprints survive line/column shifts.
abstract interface class Rule {
  /// Stable kebab-case identifier for this rule (e.g. `unused-public-exports`).
  ///
  /// Used as the [Finding.ruleId] and as a component of the fingerprint.
  String get ruleId;

  /// The analysis pillar this rule belongs to.
  ///
  /// Used by [AnalysisRunner] for category-scoped commands such as `loam a11y`.
  /// Category membership is determined by this value — never by ruleId string
  /// prefixes (Invariant 1: semantics over syntax).
  RuleCategory get category;

  /// Analyses [result] and returns all [Finding]s produced by this rule.
  ///
  /// Returns an empty list when no findings are present. Never throws in
  /// normal operation.
  List<Finding> run(ProjectLoadResult result);
}

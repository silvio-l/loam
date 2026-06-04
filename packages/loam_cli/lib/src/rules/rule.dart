import '../loader/project_loader.dart';
import '../model/finding.dart';

/// The plugin contract for every loam.dev analysis capability.
///
/// A [Rule] receives the fully resolved project ([ProjectLoadResult]) and
/// returns zero or more [Finding]s. It has no knowledge of severity thresholds,
/// baselines, or output formatting — those concerns belong to the gate and
/// reporter layers.
///
/// Implementations must:
/// - provide a stable [ruleId] in kebab-case (e.g. `unused-public-exports`).
/// - be deterministic: identical inputs must produce identical outputs
///   (Invariant 4 — reproducibility).
/// - compute each [Finding.fingerprint] via [computeFingerprint] so that
///   fingerprints survive line/column shifts.
abstract interface class Rule {
  /// Stable kebab-case identifier for this rule (e.g. `unused-public-exports`).
  ///
  /// Used as the [Finding.ruleId] and as a component of the fingerprint.
  String get ruleId;

  /// Analyses [result] and returns all [Finding]s produced by this rule.
  ///
  /// Returns an empty list when no findings are present. Never throws in
  /// normal operation.
  List<Finding> run(ProjectLoadResult result);
}

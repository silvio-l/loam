/// A single entry in the baseline — the authoritative diff key plus readable
/// non-authoritative context for git diffs and human inspection.
///
/// Only [fingerprint] is used for diffing; the other fields are informational.
class BaselineFinding {
  const BaselineFinding({
    required this.fingerprint,
    required this.ruleId,
    required this.filePath,
    required this.line,
    required this.message,
  });

  /// Authoritative diff key (position-robust, stable across line shifts).
  final String fingerprint;

  /// Non-authoritative context — for human inspection and git-diff readability.
  final String ruleId;
  final String filePath;
  final int line;
  final String message;
}

/// The persisted baseline state read from `baseline.json`.
class Baseline {
  const Baseline({
    required this.schemaVersion,
    required this.rulesetVersion,
    required this.findings,
  });

  /// Schema version for forward-compatibility (currently 1).
  ///
  /// Additional top-level fields (e.g. `promptVersion`) can be added
  /// without incrementing this version (D8 — additively extensible).
  final int schemaVersion;

  /// Ruleset identifier derived from the active rule set (e.g. `ruleset@<n>`).
  final String rulesetVersion;

  /// Stably sorted findings (same order as [AnalysisRunner] output).
  final List<BaselineFinding> findings;
}

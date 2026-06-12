import '../model/finding.dart';

/// Coarse scope statistics for one analysis run.
///
/// Answers "did the scan actually cover the right area, and how big is it?" —
/// the context a reader needs before trusting a finding count (or a clean
/// result). Computed by the `AnalysisRunner` from the loaded project; rendered
/// by every reporter in a format that fits the medium.
class ScanStats {
  /// Creates a [ScanStats].
  const ScanStats({
    required this.filesAnalyzed,
    required this.libFilesAnalyzed,
    required this.linesAnalyzed,
    required this.rulesRun,
  });

  /// Total first-party Dart files the analyzer resolved for this run.
  final int filesAnalyzed;

  /// How many of [filesAnalyzed] live under the package's `lib/` directory —
  /// the subset the structural rules (e.g. `complexity-hotspots`) measure.
  final int libFilesAnalyzed;

  /// Total source lines across all [filesAnalyzed] files.
  final int linesAnalyzed;

  /// The rule IDs that actually ran this scan (post-config), sorted. Lets a
  /// reader confirm every expected rule executed — not just the one that fired.
  final List<String> rulesRun;
}

/// The immutable value object that every [Reporter] receives.
///
/// Bundles all information any renderer might need so the [Reporter]
/// interface stays stable as new formats (sarif/json/markdown/html) are
/// added in later sprints.
///
/// [findings] are already deterministically sorted by the [AnalysisRunner]
/// (filePath → line → fingerprint), so reporters must preserve that order.
///
/// [isTty] is injected by the calling command (which reads `stdout.hasTerminal`)
/// rather than read directly in the reporter, keeping the reporter unit-testable
/// and side-effect-free (Invariant 4).
class ReportPayload {
  /// Creates a [ReportPayload].
  const ReportPayload({
    required this.findings,
    required this.projectRoot,
    required this.rulesetVersion,
    required this.toolVersion,
    required this.isTty,
    this.suppressedCount = 0,
    this.stats,
  });

  /// All findings from the current run, pre-sorted by the [AnalysisRunner].
  final List<Finding> findings;

  /// How many findings the active rules produced but suppression removed
  /// (`// loam-ignore:` directives and `loam.yaml` globs combined).
  ///
  /// Defaults to `0`. Reporters surface this so a `0 findings — clean` result
  /// is never mistaken for "nothing to look at" when findings were in fact
  /// knowingly suppressed — the difference an agent (or human) needs to
  /// reconcile a clean `scan` against a `health` hotspot table.
  final int suppressedCount;

  /// Coarse scope statistics for this run (files/lines analysed, rules run),
  /// or `null` when the caller did not compute them (e.g. `gate`/`baseline`,
  /// where scope context is not part of the contract). Reporters render it
  /// only when present.
  final ScanStats? stats;

  /// Absolute path to the project root (used for relative SARIF URIs etc.).
  final String projectRoot;

  /// Content-addressed version string for the active rule set
  /// (e.g. `ruleset@abc12345`). Feeds reproducibility metadata.
  final String rulesetVersion;

  /// Tool version (mirrors pubspec.yaml via `loamVersion`). Feeds SARIF block.
  final String toolVersion;

  /// Whether the output sink is a terminal (true) or a pipe/file (false).
  ///
  /// The calling command reads `stdout.hasTerminal` and passes the value here,
  /// so reporters never touch I/O directly (Invariant 4 — pure renderer).
  final bool isTty;
}

/// Pure renderer: converts a [ReportPayload] to a formatted [String].
///
/// Implementations MUST be pure functions:
/// - No I/O (no reading from stdin, no writing to stdout/files).
/// - No threshold/gate/exit-code logic.
/// - Same input always produces the same output (Invariant 5).
///
/// The calling command is responsible for writing the returned string and
/// determining the exit code.
abstract interface class Reporter {
  /// Renders [payload] to a formatted string.
  ///
  /// Pure function — no side effects, no thresholds, no exit logic.
  String render(ReportPayload payload);
}

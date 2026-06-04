import '../model/finding.dart';

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
  const ReportPayload({
    required this.findings,
    required this.projectRoot,
    required this.rulesetVersion,
    required this.toolVersion,
    required this.isTty,
  });

  /// All findings from the current run, pre-sorted by the [AnalysisRunner].
  final List<Finding> findings;

  /// Absolute path to the project root (used for relative SARIF URIs etc.).
  final String projectRoot;

  /// Content-addressed version string for the active rule set
  /// (e.g. `ruleset@abc12345`). Feeds reproducibility metadata.
  final String rulesetVersion;

  /// Tool version from pubspec.yaml (e.g. `0.0.2`). Feeds SARIF tool block.
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

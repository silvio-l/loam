import 'severity.dart';
export 'severity.dart';

/// A single result emitted by a `Rule`.
///
/// The [fingerprint] is a position-robust stable hash used by the
/// `BaselineEngine` to diff findings across runs (see CONTEXT.md). Note that
/// [line]/[column] are presentation-only: they feed precise highlighting in the
/// SARIF and HTML reporters, but they are deliberately NOT part of the
/// fingerprint — otherwise the baseline would churn on every line shift.
///
/// [column] is optional: file- or line-level findings (e.g. an unused export)
/// have no meaningful column. When present, both are 1-based to match SARIF
/// region semantics.
class Finding {
  /// Creates a [Finding]; [column], [kind] and [remedy] are optional.
  const Finding({
    required this.ruleId,
    required this.severity,
    required this.filePath,
    required this.line,
    required this.message,
    required this.fingerprint,
    this.column,
    this.kind,
    this.remedy,
  });

  /// Identifier of the rule that produced this finding.
  final String ruleId;

  /// Severity of the finding.
  final Severity severity;

  /// Project-relative path of the file the finding refers to.
  final String filePath;

  /// 1-based line of the finding.
  final int line;

  /// 1-based column, or `null` for file-/line-level findings.
  final int? column;

  /// Human-readable description of the finding.
  final String message;

  /// Machine-readable classifier that removes the interpretation gap an AI
  /// agent would otherwise fill itself (the root cause of mis-triage like
  /// "those are just build() methods" or "that cycle is a standard pattern").
  ///
  /// Stable, lowercase-hyphenated tokens scoped per rule, e.g.
  /// `flutter-widget-build` vs `logic` (complexity-hotspots), or
  /// `interface-impl-cycle` vs `bidirectional-cycle` (circular-dependencies).
  /// `null` only for findings predating the agent-proof message contract.
  final String? kind;

  /// The concrete next action a consumer (human or agent) should take — phrased
  /// imperatively, naming the fix, not just restating the problem. Pairs with
  /// [kind] to make a finding hard to rationalise away. `null` only for
  /// findings predating the contract.
  final String? remedy;

  /// Position-robust stable hash used by the baseline to diff findings across runs.
  final String fingerprint;

  @override
  String toString() {
    final location = column == null ? '$line' : '$line:$column';
    return '[$ruleId] $filePath:$location $message';
  }
}

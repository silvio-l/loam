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
  const Finding({
    required this.ruleId,
    required this.severity,
    required this.filePath,
    required this.line,
    required this.message,
    required this.fingerprint,
    this.column,
  });

  final String ruleId;
  final Severity severity;
  final String filePath;

  /// 1-based line of the finding.
  final int line;

  /// 1-based column, or `null` for file-/line-level findings.
  final int? column;
  final String message;
  final String fingerprint;

  @override
  String toString() {
    final location = column == null ? '$line' : '$line:$column';
    return '[$ruleId] $filePath:$location $message';
  }
}

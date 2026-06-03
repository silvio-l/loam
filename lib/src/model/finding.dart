/// Severity of a [Finding].
enum Severity { info, warning, error }

/// A single result emitted by a `Rule`.
///
/// The [fingerprint] is a position-robust stable hash used by the
/// `BaselineEngine` to diff findings across runs (see CONTEXT.md).
class Finding {
  const Finding({
    required this.ruleId,
    required this.severity,
    required this.filePath,
    required this.line,
    required this.message,
    required this.fingerprint,
  });

  final String ruleId;
  final Severity severity;
  final String filePath;
  final int line;
  final String message;
  final String fingerprint;

  @override
  String toString() => '[$ruleId] $filePath:$line $message';
}

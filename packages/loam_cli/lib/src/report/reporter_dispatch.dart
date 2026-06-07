import 'human_reporter.dart';
import 'json_reporter.dart';
import 'markdown_reporter.dart';
import 'reporter.dart';
import 'sarif_reporter.dart';

/// Thrown when a format is recognised but not yet implemented.
///
/// The calling command should catch this and print a clear message to stderr
/// (exit code 64 / EX_USAGE) rather than crashing with a stack trace.
class FormatNotImplementedError extends Error {
  FormatNotImplementedError(this.format);

  /// The requested format string (e.g. `'json'`).
  final String format;

  @override
  String toString() =>
      'loam: output format "$format" is not yet implemented '
      '(coming in a later sprint). Use --format human or --format sarif.';
}

/// Returns the [Reporter] for [format].
///
/// - `'human'`    → [HumanReporter]
/// - `'sarif'`    → [SarifReporter]
/// - `'json'`     → [JsonReporter]
/// - `'markdown'` → [MarkdownReporter]
/// - `'html'`     → throws [FormatNotImplementedError]
///
/// The calling command is responsible for catching [FormatNotImplementedError]
/// and converting it to a clean user-facing message (exit code 64).
Reporter reporterFor(String format) {
  return switch (format) {
    'human' => const HumanReporter(),
    'sarif' => const SarifReporter(),
    'json' => const JsonReporter(),
    'markdown' => const MarkdownReporter(),
    'html' => throw FormatNotImplementedError(format),
    _ => throw ArgumentError.value(format, 'format', 'Unknown output format.'),
  };
}

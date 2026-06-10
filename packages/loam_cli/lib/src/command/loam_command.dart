import 'dart:io';

import 'package:args/command_runner.dart';

/// Abstract base for all loam.dev sub-commands.
///
/// Provides:
///   - typed access to the global `--format` flag via [format]
///   - [notImplemented] helper for stub commands
///   - exit-code convention (0 = success, 64 = usage error — enforced at
///     runner level; individual commands return 0/non-zero ints)
abstract class LoamCommand extends Command<int> {
  /// Base constructor for all loam.dev sub-commands.
  LoamCommand();

  /// The output format requested by the caller.
  ///
  /// Reads the global `--format` option from [globalResults].
  /// Returns `'human'` when the flag is absent (should not happen in
  /// practice, as a default is registered at runner level).
  String get format => globalResults?['format'] as String? ?? 'human';

  /// Explicit report file path from the global `--output` option, or `null`.
  ///
  /// When set, the rendered report is written to this file instead of stdout.
  /// For `--format html` the report is always written to a file (defaulting to
  /// `loam-report.html`) regardless of this option.
  String? get outputPath => globalResults?['output'] as String?;

  /// Whether the user passed the global `--no-open` flag to suppress the
  /// browser auto-open for `--format html`.
  bool get noOpen => globalResults?['no-open'] as bool? ?? false;

  /// Writes a uniform "not yet implemented" line and returns exit code 0.
  ///
  /// [hint] is a short free-text note (e.g. the planned tracer rule).
  Future<int> notImplemented(String hint) async {
    stdout.writeln('loam $name: not yet implemented ($hint)');
    return 0;
  }
}

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
  /// The output format requested by the caller.
  ///
  /// Reads the global `--format` option from [globalResults].
  /// Returns `'human'` when the flag is absent (should not happen in
  /// practice, as a default is registered at runner level).
  String get format => globalResults?['format'] as String? ?? 'human';

  /// Writes a uniform "not yet implemented" line and returns exit code 0.
  ///
  /// [hint] is a short free-text note (e.g. the planned tracer rule).
  Future<int> notImplemented(String hint) async {
    stdout.writeln('loam $name: not yet implemented ($hint)');
    return 0;
  }
}

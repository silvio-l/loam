import 'dart:io';

import 'package:args/command_runner.dart';

import '../progress/progress_sink.dart';
import '../progress/should_show_progress.dart';
import '../progress/tty_progress_renderer.dart';

/// Live-progress policy + renderer for one command invocation.
///
/// [showProgress] is the resolved on/off decision (see [shouldShowProgress]);
/// [sink] is the matching [ProgressSink] — a [TtyProgressRenderer] when on,
/// [NoopProgressSink] otherwise. Bundled together so a single
/// [LoamCommand.resolveProgress] call yields both without recomputing the
/// policy (and, critically, without constructing a second
/// [TtyProgressRenderer] instance whose state would then be split across
/// the load and analyse phases of the same run).
typedef ProgressResolution = ({bool showProgress, ProgressSink sink});

/// Abstract base for all loam.dev sub-commands.
///
/// Provides:
///   - typed access to the global `--format` flag via [format]
///   - [resolveProgress] — the shared live-progress seam every analysing
///     command (`scan`, `gate`, `baseline`, `slop`, `a11y`, `health`) wires
///     into its [package:loam/src/loader/project_loader.dart] /
///     [package:loam/src/runner/analysis_runner.dart] calls
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

  /// Resolves whether live progress should be shown for this invocation and
  /// builds the matching [ProgressSink] — the single shared seam behind the
  /// `--no-progress` rollout across every analysing command.
  ///
  /// Precedence (highest to lowest): `--no-progress` (CLI) >
  /// `LOAM_NO_PROGRESS` (env) > `CI` (env) > TTY auto-detection. Mirrors the
  /// `--no-open` pattern (see [shouldShowProgress]).
  ///
  /// Call this exactly once per `run()` and reuse the result for every
  /// [package:loam/src/loader/project_loader.dart] / `AnalysisRunner` call in
  /// that invocation — calling it again would construct a second
  /// [TtyProgressRenderer], splitting its running state across phases.
  ProgressResolution resolveProgress() {
    final show = shouldShowProgress(
      isTty: stdout.hasTerminal,
      noProgressFlag: globalResults?['no-progress'] as bool? ?? false,
      environment: Platform.environment,
    );
    return (
      showProgress: show,
      sink: show ? TtyProgressRenderer() : const NoopProgressSink(),
    );
  }

  /// Writes a uniform "not yet implemented" line and returns exit code 0.
  ///
  /// [hint] is a short free-text note (e.g. the planned tracer rule).
  Future<int> notImplemented(String hint) async {
    stdout.writeln('loam $name: not yet implemented ($hint)');
    return 0;
  }
}

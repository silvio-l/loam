import 'dart:async';

import '../model/finding.dart';
import 'watch_session.dart';

/// Formats one finding line of a watch update.
String _line(String sign, Finding f) {
  final column = f.column == null ? '' : ':${f.column}';
  return '  $sign [${f.ruleId}] ${f.filePath}:${f.line}$column ${f.message}';
}

/// Renders a follow-up run: what triggered it, the totals, and the findings
/// that appeared (`+`) or went away (`-`). The initial run is rendered by the
/// caller as a full report instead.
String renderWatchDelta(WatchUpdate update) {
  const shown = 3;
  final paths = update.changedPaths;
  final changed = paths.isEmpty
      ? 'changed'
      : '${paths.take(shown).join(', ')}'
            '${paths.length > shown ? ' (+${paths.length - shown} more)' : ''}'
            ' changed';
  final n = update.findings.length;
  final buffer = StringBuffer(
    'loam watch: $changed -> $n finding${n == 1 ? '' : 's'} '
    '(+${update.added.length} new, -${update.resolved.length} resolved)\n',
  );
  for (final f in update.added) {
    buffer.writeln(_line('+', f));
  }
  for (final f in update.resolved) {
    buffer.writeln(_line('-', f));
  }
  return buffer.toString();
}

/// Drives a [WatchSession] for the CLI and returns the exit code.
///
/// The first run prints the full report ([renderFull]); later runs print
/// [renderWatchDelta]. Status and errors go to [err]. The first event on
/// [stopRequests] (a signal in production) ends the session cleanly and the
/// result is `0`; if writing the output fails the watch stops, reports it once on [err] and returns `1`; an error of the initial run propagates to the caller so the
/// CLI maps it like it does for `scan`.
Future<int> runWatch({
  required String root,
  required Stream<String> changes,
  required Future<List<Finding>> Function() analyze,
  required String Function(List<Finding> findings) renderFull,
  required StringSink out,
  required StringSink err,
  required Stream<void> stopRequests,
  Duration debounce = kDefaultWatchDebounce,
  TimerFactory createTimer = Timer.new,
}) async {
  final session = WatchSession(
    root: root,
    changes: changes,
    analyze: analyze,
    debounce: debounce,
    createTimer: createTimer,
    onUpdate: (update) {
      if (update.error != null) {
        err.writeln(
          'loam watch: analysis failed (${update.error}) - still watching, '
          'the next change retries.',
        );
      } else if (update.isInitial) {
        out.write(renderFull(update.findings));
        err.writeln('loam watch: watching $root - press Ctrl+C to stop.');
      } else {
        out.write(renderWatchDelta(update));
      }
    },
  );
  final stopListener = stopRequests.listen((_) => unawaited(session.stop()));
  try {
    await session.run();
  } finally {
    await stopListener.cancel();
  }
  final outputError = session.outputError;
  if (outputError != null) {
    // Reported once; exit 1 because the watch ended without being asked to.
    try {
      err.writeln(
        'loam watch: cannot write output ($outputError) - stopped. '
        'Check that the terminal or pipe is still open, then start `loam watch` again.',
      );
      // loam-ignore: slop-empty-catch – stderr may be the broken stream too; there is nowhere left to report to.
    } on Object {
      // Nothing to do.
    }
    return 1;
  }
  err.writeln('loam watch: stopped.');
  return 0;
}

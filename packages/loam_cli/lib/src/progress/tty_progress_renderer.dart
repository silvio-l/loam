import 'dart:io' as io;

import 'progress_sink.dart';
import 'render_progress_bar.dart';

/// Renders live progress to stderr using carriage-return repaint.
///
/// Each [startPhase] shows a phase name; each [advance] repaints the current
/// line with an updated bar, counter, and defensive ETA. [endPhase] clears the
/// line so that subsequent report output or error messages appear on a fresh
/// line.
///
/// This renderer lives in the CLI layer and is the only place that knows about
/// stderr, ANSI, or terminal geometry. Compute layers ([ProjectLoader],
/// [AnalysisRunner]) interact only through the abstract [ProgressSink].
///
/// [stderrSink] defaults to [io.stderr]; override in tests to capture output.
/// [terminalColumns] defaults to [io.stdout.terminalColumns] with a fallback of
/// 80 when the terminal width is not available.
class TtyProgressRenderer implements ProgressSink {
  /// Creates a [TtyProgressRenderer].
  TtyProgressRenderer({io.IOSink? stderrSink, int? terminalColumns})
    : _stderr = stderrSink ?? io.stderr,
      _columns = terminalColumns ?? _resolveColumns();

  final io.IOSink _stderr;
  final int _columns;

  String _label = '';
  int _current = 0;
  int? _total;
  final _stopwatch = Stopwatch();
  bool _lineActive = false;

  static const _fallbackColumns = 80;
  static const _minBarWidth = 4;
  static const _maxBarWidth = 40;

  // ETA is only shown once at least this fraction has been completed.
  static const _etaThreshold = 0.1;

  static int _resolveColumns() {
    try {
      return io.stdout.terminalColumns;
    } catch (_) {
      return _fallbackColumns;
    }
  }

  // ---------------------------------------------------------------------------
  // ProgressSink interface
  // ---------------------------------------------------------------------------

  @override
  void startPhase(String label, {int? total}) {
    // Clear any previous line before starting a new phase.
    if (_lineActive) _clearLine();
    _label = label;
    _current = 0;
    _total = total;
    _stopwatch
      ..reset()
      ..start();
    _lineActive = true;
    _repaint();
  }

  @override
  void advance([int delta = 1]) {
    _current += delta;
    if (_lineActive) _repaint();
  }

  @override
  void endPhase() {
    _clearLine();
    _stopwatch.stop();
  }

  // ---------------------------------------------------------------------------
  // Rendering helpers
  // ---------------------------------------------------------------------------

  void _repaint() {
    final line = _buildLine();
    // Truncate to terminal width to prevent wrap-around.
    final safe = line.length > _columns ? line.substring(0, _columns) : line;
    _stderr.write('\r$safe');
  }

  /// Clears the current progress line using CR + ANSI erase-to-end-of-line.
  void _clearLine() {
    if (!_lineActive) return;
    _stderr.write('\r\x1B[K');
    _lineActive = false;
  }

  String _buildLine() {
    final total = _total;
    final current = _current;

    // Counter: "N/M" or empty for indeterminate.
    final countStr = total != null ? '$current/$total' : '';

    // ETA: only after etaThreshold fraction is done and total is known.
    var etaStr = '';
    if (total != null && total > 0 && current > 0 && _stopwatch.isRunning) {
      final ratio = current / total;
      if (ratio >= _etaThreshold) {
        final elapsed = _stopwatch.elapsed;
        final remaining = elapsed * ((total - current) / current);
        etaStr = '~${_formatDuration(remaining.inSeconds)}';
      }
    }

    // Bar width: whatever is left after accounting for fixed parts.
    //
    //   "LABEL [BAR] COUNT ETA"
    //   overhead = label + 1 (space) + 2 (brackets)
    //            + (1 + count.length) if count non-empty
    //            + (1 + eta.length)   if eta non-empty
    var overhead = _label.length + 3; // label + ' [' + ']'
    if (countStr.isNotEmpty) overhead += 1 + countStr.length;
    if (etaStr.isNotEmpty) overhead += 1 + etaStr.length;
    final barWidth = (_columns - overhead).clamp(_minBarWidth, _maxBarWidth);

    final bar = renderProgressBar(
      current: current,
      total: total ?? 0,
      width: barWidth,
    );

    final parts = [_label, bar];
    if (countStr.isNotEmpty) parts.add(countStr);
    if (etaStr.isNotEmpty) parts.add(etaStr);
    return parts.join(' ');
  }

  static String _formatDuration(int totalSeconds) {
    if (totalSeconds < 60) return '${totalSeconds}s';
    final m = totalSeconds ~/ 60;
    final s = totalSeconds % 60;
    return '${m}m${s}s';
  }
}

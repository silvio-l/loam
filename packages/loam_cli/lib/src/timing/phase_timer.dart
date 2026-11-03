/// Wall-clock measurement of the analysis phases and individual rules, behind
/// the global `--timing` flag.
///
/// The clock is injected ([Duration] since an arbitrary origin) so the
/// bookkeeping and rendering are testable with simulated time. Production code
/// uses [PhaseTimer.wallClock].
class PhaseTimer {
  /// Creates a timer reading elapsed time from [now].
  PhaseTimer(this._now, {this.onEvent}) : _origin = _now();

  /// Creates a timer backed by a real [Stopwatch].
  factory PhaseTimer.wallClock({PhaseEventListener? onEvent}) {
    final watch = Stopwatch()..start();
    return PhaseTimer(() => watch.elapsed, onEvent: onEvent);
  }

  /// Notified when a phase or item starts and stops. The run watchdog uses it
  /// to name the place where a run hangs.
  final PhaseEventListener? onEvent;

  /// The timer the current CLI invocation reports into, or `null` when
  /// `--timing` is off. Set by the entry point, read by the loader and runner,
  /// so no analysing command needs to pass it along.
  static PhaseTimer? active;

  final Duration Function() _now;
  final Duration _origin;
  final List<TimedEntry> _entries = [];

  /// Recorded entries in the order they started.
  List<TimedEntry> get entries => List.unmodifiable(_entries);

  /// Time elapsed since this timer was created.
  Duration get total => _now() - _origin;

  /// Starts [label] and returns the function that stops it.
  ///
  /// [depth] is the nesting level used for indentation (0 = phase, 1 = item
  /// inside a phase such as a single rule). [detail] is an optional note such
  /// as a file count.
  void Function() begin(String label, {int depth = 0, String? detail}) {
    final start = _now();
    onEvent?.call(label, depth, started: true);
    final index = _entries.length;
    _entries.add(
      TimedEntry(label, Duration.zero, depth: depth, detail: detail),
    );
    var stopped = false;
    return () {
      if (stopped) return;
      stopped = true;
      onEvent?.call(label, depth, started: false);
      final old = _entries[index];
      _entries[index] = TimedEntry(
        label,
        _now() - start,
        depth: depth,
        detail: old.detail,
      );
    };
  }

  /// Runs [action], recording its duration under [label].
  T measure<T>(String label, T Function() action, {int depth = 0}) {
    final stop = begin(label, depth: depth);
    try {
      return action();
    } finally {
      stop();
    }
  }

  /// Runs [action], recording it in the [active] timer when `--timing` is on.
  static T time<T>(String label, T Function() action) {
    final timer = active;
    return timer == null ? action() : timer.measure(label, action);
  }

  /// Renders the report printed to stderr after the run.
  String render() {
    final lines = <String>['loam timing'];
    final width = _entries.fold<int>(
      5,
      (w, e) =>
          w < e.label.length + e.depth * 2 ? e.label.length + e.depth * 2 : w,
    );
    for (final e in _entries) {
      final name = '${'  ' * e.depth}${e.label}'.padRight(width);
      final detail = e.detail == null ? '' : '  (${e.detail})';
      lines.add('  $name  ${formatDuration(e.duration).padLeft(8)}$detail');
    }
    lines.add(
      '  ${'total'.padRight(width)}  '
      '${formatDuration(total).padLeft(8)}',
    );
    return '${lines.join('\n')}\n';
  }

  /// Formats [d] as milliseconds below one second, otherwise seconds.
  static String formatDuration(Duration d) {
    final ms = d.inMilliseconds;
    if (ms < 1000) return '$ms ms';
    return '${(ms / 1000).toStringAsFixed(2)} s';
  }
}

/// Listener for [PhaseTimer.onEvent].
typedef PhaseEventListener =
    void Function(String label, int depth, {required bool started});

/// One measured phase or rule.
class TimedEntry {
  /// Creates a [TimedEntry].
  const TimedEntry(this.label, this.duration, {this.depth = 0, this.detail});

  /// Phase name or rule id.
  final String label;

  /// Measured duration.
  final Duration duration;

  /// Nesting level (0 = phase, 1 = item within a phase).
  final int depth;

  /// Optional note such as a file count.
  final String? detail;
}

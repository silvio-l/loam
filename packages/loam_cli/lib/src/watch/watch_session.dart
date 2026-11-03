import 'dart:async';

import 'package:path/path.dart' as p;

import '../model/finding.dart';
import '../model/project_path.dart';

/// Starts a timer; injectable so tests drive the debounce with simulated time.
typedef TimerFactory = Timer Function(Duration delay, void Function() action);

/// The default quiet period after the last file event before a run starts.
///
/// Editors and formatters write several files in quick succession; 300 ms
/// folds such a burst into one run without making a single save feel slow.
const Duration kDefaultWatchDebounce = Duration(milliseconds: 300);

/// The outcome of one analysis run inside a [WatchSession].
class WatchUpdate {
  /// Creates a [WatchUpdate].
  const WatchUpdate({
    required this.run,
    required this.findings,
    required this.added,
    required this.resolved,
    required this.changedPaths,
    this.error,
  });

  /// 1 for the initial run, then counting up.
  final int run;

  /// All findings of this run (the same as a full `loam scan`). When [error]
  /// is set, the findings of the last successful run.
  final List<Finding> findings;

  /// Findings that were not in the previous run (by fingerprint). On the
  /// initial run, every finding.
  final List<Finding> added;

  /// Findings of the previous run that are gone now.
  final List<Finding> resolved;

  /// Project-relative POSIX paths whose events triggered this run (sorted);
  /// empty for the initial run.
  final List<String> changedPaths;

  /// Set when this run failed (e.g. a broken `loam.yaml`); the session keeps
  /// watching and the next change retries.
  final Object? error;

  /// Whether this is the initial run.
  bool get isInitial => run == 1;
}

/// Whether a change to [path] can alter the analysis result of the project at
/// [root]: a Dart file, `pubspec.yaml`, `analysis_options.yaml` or `loam.yaml`
/// outside `.dart_tool`, `build` and hidden directories.
///
/// Events on loam's own outputs (`baseline.json`, the HTML report, the
/// analyzer store under `.dart_tool`) are ignored on purpose, so a run can
/// never trigger itself.
bool isRelevantChange(String root, String path) {
  final relative = p.relative(p.normalize(p.join(root, path)), from: root);
  if (relative.startsWith('..')) return false;
  final parts = p.split(relative);
  for (final dir in parts.take(parts.length - 1)) {
    if (dir == 'build' || dir.startsWith('.')) return false;
  }
  final name = parts.last;
  return name.endsWith('.dart') ||
      name == 'pubspec.yaml' ||
      name == 'analysis_options.yaml' ||
      name == 'loam.yaml';
}

/// Re-runs a full analysis after file changes and reports what changed.
///
/// **Correctness over cleverness.** Every run analyses the whole project, so
/// findings that depend on other files (import graph, cycles, unused exports,
/// duplicates) are never lost and each result equals a full `loam scan` of the
/// same state. What stays warm between runs is the analyzer's summary store
/// (passed to [analyze] by the caller), which is what makes a run after a
/// small edit fast.
///
/// Time and file events are injected: [changes] is any stream of changed
/// paths, [createTimer] defaults to a real [Timer]. Tests feed events and
/// advance a fake clock instead of waiting.
///
/// Behaviour:
/// - The first run starts at once; later runs start [debounce] after the last
///   relevant event (a burst becomes one run).
/// - Events during a run are collected and trigger exactly one follow-up run.
/// - A failing run is reported through [WatchUpdate.error] and keeps the
///   session alive, except the initial run, whose error propagates from [run].
/// - If [onUpdate] throws, the session stops itself and keeps the error in
///   [outputError]; nothing escapes unhandled.
/// - [stop] cancels the pending timer and the event subscription, waits for
///   a running analysis to finish and completes [run]. No timer or listener
///   outlives it.
class WatchSession {
  /// Creates a session for the project at [root].
  WatchSession({
    required this.root,
    required this.changes,
    required this.analyze,
    required this.onUpdate,
    this.debounce = kDefaultWatchDebounce,
    this.createTimer = Timer.new,
    bool Function(String root, String path) isRelevant = isRelevantChange,
  }) : _isRelevant = isRelevant;

  /// Absolute project root; event paths are made project-relative to it.
  final String root;

  /// Absolute or root-relative paths of changed files.
  final Stream<String> changes;

  /// Runs one full analysis. Called once per run, never concurrently.
  final Future<List<Finding>> Function() analyze;

  /// Receives every run's result.
  final void Function(WatchUpdate update) onUpdate;

  /// Quiet period after the last relevant event before a run starts.
  final Duration debounce;

  /// Timer source (real by default).
  final TimerFactory createTimer;

  final bool Function(String root, String path) _isRelevant;

  final Set<String> _pending = {};
  final Completer<void> _stopped = Completer<void>();
  StreamSubscription<String>? _subscription;
  Timer? _timer;
  Future<void>? _inflight;
  List<Finding> _last = const [];
  int _runs = 0;

  /// Set when [onUpdate] threw (e.g. a closed stdout): the session has then
  /// stopped itself and [run] completed normally.
  Object? outputError;

  (Object, StackTrace)? _initialFailure;
  bool _running = false;
  bool _stopping = false;

  /// Runs the initial analysis, then watches until [stop] is called.
  ///
  /// Rethrows an error of the initial run (nothing to watch without a working
  /// analysis) after releasing the subscription.
  Future<void> run() async {
    _subscription = changes.listen(_onEvent);
    await (_inflight = _analyzeOnce());
    final failure = _initialFailure;
    if (failure != null) {
      await stop();
      Error.throwWithStackTrace(failure.$1, failure.$2);
    }
    await _stopped.future;
    await _inflight;
  }

  /// Ends the session; safe to call more than once and from a signal handler.
  Future<void> stop() async {
    if (_stopping) return;
    _stopping = true;
    _timer?.cancel();
    _timer = null;
    await _subscription?.cancel();
    _subscription = null;
    if (!_stopped.isCompleted) _stopped.complete();
    await _inflight;
  }

  void _onEvent(String path) {
    if (_stopping || !_isRelevant(root, path)) return;
    _pending.add(
      projectRelativePosixPath(p.normalize(p.join(root, path)), root),
    );
    // A running analysis picks the change up through _scheduleIfPending once
    // it is done; otherwise restart the quiet period.
    if (_running) return;
    _timer?.cancel();
    _timer = createTimer(debounce, _fire);
  }

  void _fire() {
    _timer = null;
    if (_stopping) return;
    _inflight = _analyzeOnce();
    unawaited(_inflight);
  }

  void _scheduleIfPending() {
    if (_stopping || _pending.isEmpty) return;
    _timer?.cancel();
    _timer = createTimer(debounce, _fire);
  }

  Future<void> _analyzeOnce() async {
    _running = true;
    final changed = _pending.toList()..sort();
    _pending.clear();
    final runNumber = ++_runs;
    WatchUpdate? update;
    try {
      final findings = await analyze();
      final previous = {for (final f in _last) f.fingerprint};
      final current = {for (final f in findings) f.fingerprint};
      update = WatchUpdate(
        run: runNumber,
        findings: findings,
        added: [
          for (final f in findings)
            if (!previous.contains(f.fingerprint)) f,
        ],
        resolved: [
          for (final f in _last)
            if (!current.contains(f.fingerprint)) f,
        ],
        changedPaths: changed,
      );
      _last = findings;
    } on Object catch (error, stack) {
      if (runNumber == 1) {
        _initialFailure = (error, stack);
        _running = false;
        return;
      }
      update = WatchUpdate(
        run: runNumber,
        findings: _last,
        added: const [],
        resolved: const [],
        changedPaths: changed,
        error: error,
      );
    }
    _running = false;
    try {
      onUpdate(update);
    } on Object catch (error) {
      // The output is gone (e.g. closed pipe): watching on would be blind.
      outputError = error;
      unawaited(stop());
      return;
    }
    _scheduleIfPending();
  }
}

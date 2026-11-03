import 'dart:async';
import 'dart:io';
import 'dart:isolate';

/// Exit code of a run aborted by the time limit. Follows GNU `timeout(1)`, so
/// a hook can tell it from findings (1), usage errors (64) and config
/// problems (78).
const int kTimeoutExitCode = 124;

/// Default limit for a whole run when neither `--timeout` nor `LOAM_TIMEOUT`
/// is set. Generous on purpose: it only has to catch a run that hangs, not a
/// slow one.
const Duration kDefaultRunTimeout = Duration(minutes: 10);

/// Name of the environment variable that sets the limit.
const String kRunTimeoutEnv = 'LOAM_TIMEOUT';

/// Parses a limit such as `600`, `90s`, `10m`, `1h`. `0`, `off` and `none`
/// switch the limit off and return `null`. Throws [FormatException] otherwise.
Duration? parseRunTimeout(String raw) {
  final text = raw.trim().toLowerCase();
  if (text == 'off' || text == 'none') return null;
  final match = RegExp(r'^(\d+)\s*([smh]?)$').firstMatch(text);
  if (match == null) {
    throw FormatException(
      'invalid time limit "$raw": use seconds or a number with s, m or h '
      '(for example 90s, 10m, 1h), or 0/off to disable',
    );
  }
  final value = int.tryParse(match.group(1)!);
  final factor = switch (match.group(2)) {
    'm' => 60,
    'h' => 3600,
    _ => 1,
  };
  // Cap at one year: larger values would overflow Duration into a negative
  // limit that fires at once.
  const maxSeconds = 365 * 24 * 3600;
  if (value == null || value > maxSeconds ~/ factor) {
    throw FormatException(
      'time limit "$raw" is too large: the maximum is 365 days; '
      'use 0/off to disable the limit',
    );
  }
  if (value == 0) return null;
  return Duration(seconds: value * factor);
}

/// Resolves the effective limit: `--timeout` beats [env] (`LOAM_TIMEOUT`)
/// beats [kDefaultRunTimeout]. `null` means no limit. Throws
/// [FormatException] for an unparsable value.
Duration? resolveRunTimeout({String? flag, String? env}) {
  final raw = flag ?? ((env ?? '').trim().isEmpty ? null : env);
  return raw == null ? kDefaultRunTimeout : parseRunTimeout(raw);
}

/// Formats [d] compactly (`90 s`, `10 min`, `2 h`).
String formatRunTimeout(Duration d) {
  if (d.inSeconds % 3600 == 0 && d.inSeconds >= 3600) return '${d.inHours} h';
  if (d.inSeconds % 60 == 0 && d.inSeconds >= 60) return '${d.inMinutes} min';
  return '${d.inSeconds} s';
}

/// Tracks which phase and which rule a run is in, from begin/end events.
class RunLocation {
  String? _phase;
  String? _item;

  /// A phase (depth 0) or an item inside it such as a rule (depth 1) started.
  void begin(String label, int depth) {
    if (depth == 0) {
      _phase = label;
      _item = null;
    } else {
      _item = label;
    }
  }

  /// The phase or item ended.
  void end(String label, int depth) {
    if (depth == 0) {
      if (_phase == label) _phase = null;
      _item = null;
    } else if (_item == label) {
      _item = null;
    }
  }

  /// Human-readable position, for the timeout message.
  String describe() {
    final phase = _phase;
    if (phase == null) return 'between phases (no phase active)';
    final item = _item;
    return item == null ? "phase '$phase'" : "phase '$phase', rule '$item'";
  }
}

/// Builds the stderr message printed when the limit is hit.
String formatTimeoutMessage(Duration limit, String location) =>
    'loam: aborted after ${formatRunTimeout(limit)} without finishing '
    '(exit code $kTimeoutExitCode, not a gate failure).\n'
    'It was in $location.\n'
    'Raise the limit with --timeout (for example --timeout 30m) or '
    '$kRunTimeoutEnv=30m; switch it off with --timeout 0.\n';

/// The logic of the watchdog, independent of isolates and real time: feed it
/// begin/end events, start it, and it calls [onExpire] with the message when
/// the timer created by [createTimer] fires.
class WatchdogCore {
  /// Creates a core for [limit]. [createTimer] defaults to a real [Timer];
  /// tests inject one they fire by hand.
  WatchdogCore({
    required this.limit,
    required this.onExpire,
    Timer Function(Duration, void Function())? createTimer,
  }) : _createTimer = createTimer ?? Timer.new;

  /// The run's time limit.
  final Duration limit;

  /// Called once with the complete stderr message when the limit is hit.
  final void Function(String message) onExpire;

  final Timer Function(Duration, void Function()) _createTimer;
  final RunLocation _location = RunLocation();
  Timer? _timer;

  /// Starts counting.
  void start() {
    _timer = _createTimer(limit, () {
      onExpire(formatTimeoutMessage(limit, _location.describe()));
    });
  }

  /// Records that a phase or rule started.
  void begin(String label, int depth) => _location.begin(label, depth);

  /// Records that a phase or rule ended.
  void end(String label, int depth) => _location.end(label, depth);

  /// Cancels the timer; the run finished in time.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// Runs a [WatchdogCore] in its own isolate, so it still fires when the main
/// isolate is stuck in a synchronous loop (an event-loop timer could not).
/// On expiry it prints the message to stderr and ends the process with
/// [kTimeoutExitCode].
class RunWatchdog {
  RunWatchdog._(this._isolate, this._port, this._events);

  final Isolate _isolate;
  final SendPort _port;
  final ReceivePort _events;

  /// Starts a watchdog for [limit]. Returns `null` when the limit is off.
  static Future<RunWatchdog?> start(Duration? limit) async {
    if (limit == null) return null;
    final handshake = ReceivePort();
    final isolate = await Isolate.spawn(_entry, [
      handshake.sendPort,
      limit.inMilliseconds,
    ]);
    final port = await handshake.first as SendPort;
    handshake.close();
    return RunWatchdog._(isolate, port, handshake);
  }

  /// Forwards a begin (`true`) or end (`false`) event of a phase or rule.
  void event(String label, int depth, {required bool started}) =>
      _port.send([started, label, depth]);

  /// Stops the watchdog: the run finished in time.
  void stop() {
    _port.send(null);
    _isolate.kill();
    _events.close();
  }

  static void _entry(List<Object?> args) {
    final main = args[0]! as SendPort;
    final limit = Duration(milliseconds: args[1]! as int);
    final inbox = ReceivePort();
    final core = WatchdogCore(
      limit: limit,
      onExpire: (message) {
        stderr.write(message);
        exit(kTimeoutExitCode);
      },
    );
    inbox.listen((Object? m) {
      if (m == null) {
        core.stop();
        inbox.close();
      } else if (m is List) {
        final label = m[1] as String;
        final depth = m[2] as int;
        m[0] as bool ? core.begin(label, depth) : core.end(label, depth);
      }
    });
    core.start();
    main.send(inbox.sendPort);
  }
}

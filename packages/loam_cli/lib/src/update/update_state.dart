import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'file_lock.dart';

/// What the last background update attempt did.
enum UpdateOutcomeKind {
  /// The new version was installed; the next run announces it.
  applied,

  /// The install failed; the next run prints the reason and the manual command.
  failed,
}

/// The result of one background install attempt, kept until it is reported.
class UpdateOutcome {
  /// Whether the attempt succeeded.
  final UpdateOutcomeKind kind;

  /// The version that ran when the update started.
  final Version from;

  /// The version the update tried to install.
  final Version to;

  /// Why a failed attempt failed (one short line); `null` when applied.
  final String? reason;

  /// The rule IDs of [from], so the new version can name ruleset changes.
  final List<String> previousRuleIds;

  /// Whether a run already printed this outcome (it is printed once).
  final bool reported;

  /// Creates an [UpdateOutcome].
  const UpdateOutcome({
    required this.kind,
    required this.from,
    required this.to,
    this.reason,
    this.previousRuleIds = const [],
    this.reported = false,
  });

  /// A copy marked as printed.
  UpdateOutcome markReported() => UpdateOutcome(
    kind: kind,
    from: from,
    to: to,
    reason: reason,
    previousRuleIds: previousRuleIds,
    reported: true,
  );

  Map<String, Object?> _toJson() => {
    'kind': kind.name,
    'from': from.toString(),
    'to': to.toString(),
    'reason': reason,
    'previousRuleIds': previousRuleIds,
    'reported': reported,
  };

  static UpdateOutcome _fromJson(Map<String, dynamic> json) => UpdateOutcome(
    kind: UpdateOutcomeKind.values.byName(json['kind'] as String),
    from: Version.parse(json['from'] as String),
    to: Version.parse(json['to'] as String),
    reason: json['reason'] as String?,
    previousRuleIds: [
      for (final id in (json['previousRuleIds'] as List<dynamic>? ?? const []))
        id as String,
    ],
    reported: json['reported'] as bool? ?? false,
  );
}

/// Persistent update state shared by the foreground run and the background
/// worker: the last known latest version, when it was last checked, and the
/// outcome of the last install attempt.
class UpdateState {
  /// The latest stable version seen on pub.dev, or `null` if never fetched.
  final Version? latest;

  /// When a check was last started (UTC). Throttles checks to one per day,
  /// also when the check failed (no retry storm while offline).
  final DateTime? checkedAt;

  /// The last install attempt, or `null`.
  final UpdateOutcome? outcome;

  /// Creates an [UpdateState].
  const UpdateState({this.latest, this.checkedAt, this.outcome});

  /// The empty state (nothing checked yet).
  static const empty = UpdateState();

  /// A copy with the given fields replaced.
  UpdateState copyWith({
    Version? latest,
    DateTime? checkedAt,
    UpdateOutcome? outcome,
  }) => UpdateState(
    latest: latest ?? this.latest,
    checkedAt: checkedAt ?? this.checkedAt,
    outcome: outcome ?? this.outcome,
  );

  /// Serialises the state to JSON.
  String encode() => jsonEncode({
    'latest': latest?.toString(),
    'checkedAt': checkedAt?.toIso8601String(),
    'outcome': outcome?._toJson(),
  });

  /// Parses [source]; any malformed content yields [UpdateState.empty].
  static UpdateState decode(String source) {
    try {
      final json = jsonDecode(source) as Map<String, dynamic>;
      final latest = json['latest'] as String?;
      final checkedAt = json['checkedAt'] as String?;
      final outcome = json['outcome'] as Map<String, dynamic>?;
      return UpdateState(
        latest: latest == null ? null : Version.parse(latest),
        checkedAt: checkedAt == null ? null : DateTime.parse(checkedAt),
        outcome: outcome == null ? null : UpdateOutcome._fromJson(outcome),
      );
    } on Object {
      return UpdateState.empty;
    }
  }
}

/// How often and how long to wait for the state lock before giving up.
const int _stateLockAttempts = 50;
const Duration _stateLockRetryDelay = Duration(milliseconds: 20);

/// Reads and writes [UpdateState]; injected so tests need no filesystem.
abstract interface class UpdateStateStore {
  /// The stored state, or [UpdateState.empty] when absent or unreadable.
  UpdateState read();

  /// Applies [change] to the freshly read state and persists the result, so
  /// concurrent writers each change only their own fields. Never throws.
  void update(UpdateState Function(UpdateState current) change);
}

/// [UpdateStateStore] backed by `update_state.json` in the OS cache directory.
///
/// Platform mapping:
/// - macOS:   `~/Library/Caches/loam/`
/// - Linux:   `$XDG_CACHE_HOME/loam/` or `~/.cache/loam/`
/// - Windows: `%LOCALAPPDATA%\loam\`
class FileUpdateStateStore implements UpdateStateStore {
  /// Creates a store in [directory] (defaults to [cacheDir]). Without any
  /// directory the store is inert: it reads nothing and writes nothing.
  FileUpdateStateStore({String? directory, void Function(Duration)? sleep})
    : _dir = directory ?? cacheDir,
      _sleep = sleep ?? _blockingSleep;

  final String? _dir;
  final void Function(Duration) _sleep;

  static void _blockingSleep(Duration d) => sleep(d);

  /// The directory holding the state and the worker lock, or `null` when the
  /// OS cache location cannot be determined (nothing is then stored).
  String? get directory => _dir;

  /// Returns the OS-appropriate cache directory path for loam, or `null` when
  /// the needed environment variable is missing or empty. Never a relative
  /// path: that would land in the analysed project.
  static String? get cacheDir => cacheDirFor(
    Platform.environment,
    isMacOS: Platform.isMacOS,
    isWindows: Platform.isWindows,
  );

  /// [cacheDir] for an explicit environment and platform (testable).
  static String? cacheDirFor(
    Map<String, String> env, {
    required bool isMacOS,
    required bool isWindows,
  }) {
    String? set(String key) {
      final v = env[key];
      return v == null || v.isEmpty ? null : v;
    }

    if (isWindows) {
      final base = set('LOCALAPPDATA');
      return base == null ? null : p.join(base, 'loam');
    }
    if (isMacOS) {
      final home = set('HOME');
      return home == null ? null : p.join(home, 'Library', 'Caches', 'loam');
    }
    final xdg = set('XDG_CACHE_HOME');
    if (xdg != null) return p.join(xdg, 'loam');
    final home = set('HOME');
    return home == null ? null : p.join(home, '.cache', 'loam');
  }

  String? get _path => _dir == null ? null : p.join(_dir, 'update_state.json');

  @override
  UpdateState read() {
    final path = _path;
    if (path == null) return UpdateState.empty;
    try {
      final file = File(path);
      if (!file.existsSync()) return UpdateState.empty;
      return UpdateState.decode(file.readAsStringSync());
    } on FileSystemException {
      return UpdateState.empty;
    }
  }

  @override
  void update(UpdateState Function(UpdateState current) change) {
    final dir = _dir;
    final path = _path;
    if (dir == null || path == null) return;
    final lock = FileLock('$path.lock');
    try {
      Directory(dir).createSync(recursive: true);
      if (!_acquire(lock)) return;
      try {
        // Re-read under the lock, so no concurrent change is overwritten. A
        // file that exists but cannot be read aborts the write instead of
        // replacing the stored state with an empty one.
        final file = File(path);
        final current = file.existsSync()
            ? UpdateState.decode(file.readAsStringSync())
            : UpdateState.empty;
        final next = change(current);
        // Write-then-rename so a concurrent reader never sees a torn file.
        final tmp = File('$path.$pid.tmp');
        try {
          tmp.writeAsStringSync(next.encode());
          tmp.renameSync(path);
        } on FileSystemException {
          if (tmp.existsSync()) tmp.deleteSync();
          rethrow;
        }
      } finally {
        lock.release();
      }
    } on FileSystemException {
      // A non-writable cache only costs the throttle; the run is unaffected.
      return;
    }
  }

  /// Takes the short state lock, retrying while another writer holds it (the
  /// critical section is one small file write).
  bool _acquire(FileLock lock) {
    for (var i = 0; i < _stateLockAttempts; i++) {
      if (lock.tryAcquire()) return true;
      _sleep(_stateLockRetryDelay);
    }
    return false;
  }
}

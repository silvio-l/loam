import 'dart:ffi';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'file_lock.dart';
import 'install_channel.dart';
import 'integrity.dart';
import 'latest_version_fetcher.dart';
import 'self_updater.dart';
import 'update_policy.dart';
import 'update_state.dart';

/// The name of the hidden sub-command the background worker runs as.
const String kUpdateWorkerCommand = '_update-worker';

/// Glue between the pure update logic and the running process: which install
/// this is, whether it can update itself, and how the worker is started.
/// Everything here touches [Platform], the filesystem or processes; the
/// decisions it feeds are in `update_policy.dart` and `auto_update.dart`.
class UpdateRuntime {
  /// Creates the runtime for the current process.
  UpdateRuntime() : install = InstallInfo.current();

  /// The detected install of the running loam.
  final InstallInfo install;

  bool get _runsOnDartVm {
    return isDartVmExecutable(p.basename(Platform.resolvedExecutable));
  }

  /// Whether this install may update itself (see [canSelfUpdate]).
  bool get canUpdateItself => canSelfUpdate(
    install,
    pubLockContent: install.channel == InstallChannel.pubGlobal
        ? _readPubGlobalLock()
        : null,
    hasBinaryAsset:
        install.channel == InstallChannel.binary &&
        p.basenameWithoutExtension(Platform.resolvedExecutable) == 'loam' &&
        binaryAssetName(Abi.current()) != null,
    isReleaseBinary: kIsReleaseBinary,
  );

  /// The global `pubspec.lock` next to the activated snapshot
  /// (`…/global_packages/loam/bin/<snapshot>` → `…/global_packages/loam/`).
  String? _readPubGlobalLock() {
    try {
      final packageDir = p.dirname(p.dirname(install.executablePath));
      return File(p.join(packageDir, 'pubspec.lock')).readAsStringSync();
    } on FileSystemException {
      return null;
    }
  }

  /// Starts the worker as a detached copy of this loam (it outlives this
  /// process and never writes to its terminal). Source runs and unknown
  /// layouts never start a worker: there is no stable entry point to run.
  Future<void> spawnWorker(UpdateMode mode) async {
    if (install.channel == InstallChannel.unknown) return;
    if (FileUpdateStateStore.cacheDir == null) return;
    final args = [
      if (_runsOnDartVm) install.executablePath,
      kUpdateWorkerCommand,
      if (mode == UpdateMode.auto) '--install',
    ];
    try {
      await _withLowFdLimit(
        () => Process.start(
          Platform.resolvedExecutable,
          args,
          mode: ProcessStartMode.detached,
        ),
      );
    } on ProcessException {
      // Could not start the worker: the next due run tries again.
      return;
    }
  }

  /// The installer for this channel, or `null` when it cannot self-update.
  SelfInstaller? _installer() {
    switch (install.channel) {
      case InstallChannel.pubGlobal:
        return PubGlobalInstaller(dartExecutable: Platform.resolvedExecutable);
      case InstallChannel.binary:
        final asset = binaryAssetName(Abi.current());
        if (asset == null) return null;
        return BinaryInstaller(
          asset: asset,
          swap: nativeBinarySwap(Platform.resolvedExecutable),
        );
      case InstallChannel.homebrew:
      case InstallChannel.unknown:
        return null;
    }
  }

  /// Runs the background worker once, guarded by a lock file so parallel
  /// workers never install at the same time.
  Future<void> runWorker({
    required bool installAllowed,
    required Version current,
    required List<String> currentRuleIds,
  }) async {
    final store = FileUpdateStateStore();
    final dir = store.directory;
    // No cache location: nothing could be stored or locked, so do nothing.
    if (dir == null) return;
    final lock = FileLock(p.join(dir, 'update.lock'));
    if (!lock.tryAcquire()) return;
    try {
      await UpdateWorker(
        current: current,
        currentRuleIds: currentRuleIds,
        store: store,
        fetcher: const PubDevLatestVersionFetcher(),
        installer: installAllowed && canUpdateItself ? _installer() : null,
      ).run();
    } finally {
      lock.release();
    }
  }
}

/// Soft open-files limit used while the worker is spawned.
const int _spawnFdLimit = 4096;

/// Runs [spawn] with the soft `RLIMIT_NOFILE` lowered to [_spawnFdLimit].
///
/// Before `exec`, the Dart process launcher closes every descriptor up to the
/// soft open-files limit. With a common macOS setting of 1048576 that loop
/// alone takes seconds, so the foreground run would wait for it — exactly
/// what the background check must avoid. The limit is restored right after
/// the spawn; when it cannot be read or changed the spawn runs unchanged.
Future<T> _withLowFdLimit<T>(Future<T> Function() spawn) async {
  final api = _RLimitApi.tryLoad();
  final previous = api?.readSoft();
  if (api == null || previous == null || previous <= _spawnFdLimit) {
    return spawn();
  }
  final lowered = api.writeSoft(_spawnFdLimit);
  try {
    return await spawn();
  } finally {
    if (lowered) api.writeSoft(previous);
  }
}

final class _RLimit extends Struct {
  @Uint64()
  external int current;

  @Uint64()
  external int maximum;
}

typedef _RLimitNative = Int32 Function(Int32, Pointer<_RLimit>);
typedef _RLimitDart = int Function(int, Pointer<_RLimit>);
typedef _MallocNative = Pointer<Void> Function(IntPtr);
typedef _MallocDart = Pointer<Void> Function(int);
typedef _FreeNative = Void Function(Pointer<Void>);
typedef _FreeDart = void Function(Pointer<Void>);

/// Minimal libc `getrlimit`/`setrlimit` binding for `RLIMIT_NOFILE`
/// (macOS and Linux on 64-bit, where `rlim_t` is 64 bits wide).
class _RLimitApi {
  _RLimitApi._(this._resource, DynamicLibrary libc)
    : _get = libc.lookupFunction<_RLimitNative, _RLimitDart>('getrlimit'),
      _set = libc.lookupFunction<_RLimitNative, _RLimitDart>('setrlimit'),
      _malloc = libc.lookupFunction<_MallocNative, _MallocDart>('malloc'),
      _free = libc.lookupFunction<_FreeNative, _FreeDart>('free');

  final int _resource;
  final _RLimitDart _get;
  final _RLimitDart _set;
  final _MallocDart _malloc;
  final _FreeDart _free;

  static _RLimitApi? tryLoad() {
    final resource = switch (Abi.current()) {
      Abi.macosArm64 || Abi.macosX64 => 8,
      Abi.linuxX64 || Abi.linuxArm64 => 7,
      _ => null,
    };
    if (resource == null) return null;
    try {
      return _RLimitApi._(resource, DynamicLibrary.process());
    } on ArgumentError {
      return null;
    }
  }

  T? _withLimit<T>(T? Function(Pointer<_RLimit> limit) body) {
    final raw = _malloc(sizeOf<_RLimit>());
    if (raw == nullptr) return null;
    try {
      return body(raw.cast<_RLimit>());
    } finally {
      _free(raw);
    }
  }

  int? readSoft() => _withLimit(
    (limit) => _get(_resource, limit) == 0 ? limit.ref.current : null,
  );

  bool writeSoft(int value) =>
      _withLimit((limit) {
        if (_get(_resource, limit) != 0) return false;
        limit.ref.current = value;
        return _set(_resource, limit) == 0;
      }) ??
      false;
}

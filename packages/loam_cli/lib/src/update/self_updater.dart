import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;
import 'package:pub_semver/pub_semver.dart';

import 'integrity.dart';
import 'latest_version_fetcher.dart';
import 'update_policy.dart';
import 'update_state.dart';

/// Runs an external program and returns its result (injected in tests).
typedef ProcessRunner =
    Future<ProcessResult> Function(String executable, List<String> arguments);

/// Longest a `dart pub global activate` may run (well below the 1 h lock age).
const Duration kActivateTimeout = Duration(minutes: 10);

/// Longest a `tar` extraction or the version probe may run.
const Duration kProbeTimeout = Duration(minutes: 2);

/// A [ProcessRunner] that kills the process and throws [TimeoutException]
/// when it runs longer than [timeout]. Callers treat that as a failure.
ProcessRunner boundedRunner(Duration timeout) => (executable, arguments) async {
  final process = await Process.start(executable, arguments);
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  try {
    final code = await process.exitCode.timeout(timeout);
    return ProcessResult(process.pid, code, await out, await err);
  } on TimeoutException {
    process.kill(ProcessSignal.sigkill);
    rethrow;
  }
};

/// Downloads [uri] up to [maxBytes]; `null` on any error (injected in tests).
typedef Downloader =
    Future<List<int>?> Function(Uri uri, {required int maxBytes});

/// Replaces the running binary with the verified [archive] of [target];
/// returns `null` on success or a one-line failure reason.
typedef BinarySwap =
    Future<String?> Function(List<int> archive, Version target);

/// Installs a given loam version for one install channel.
abstract interface class SelfInstaller {
  /// Installs [target]; returns `null` on success or a one-line reason.
  Future<String?> install(Version target);
}

/// Updates a `dart pub global activate loam` install.
///
/// Uses the Dart SDK that runs loam right now, so the new snapshot matches the
/// SDK of the pub cache. Pins the exact [Version] that was checked instead of
/// "latest", so a release published in between is never installed unchecked.
/// pub itself verifies the archive's SHA-256 against pub.dev.
class PubGlobalInstaller implements SelfInstaller {
  /// Creates an installer that runs `<dartExecutable> pub global activate`.
  PubGlobalInstaller({
    required String dartExecutable,
    ProcessRunner? runProcess,
  }) : _dart = dartExecutable,
       _run = runProcess ?? boundedRunner(kActivateTimeout);

  final String _dart;
  final ProcessRunner _run;

  @override
  Future<String?> install(Version target) async {
    final ProcessResult result;
    try {
      result = await _run(_dart, [
        'pub',
        'global',
        'activate',
        'loam',
        target.toString(),
      ]);
    } on TimeoutException {
      return 'dart pub global activate timed out';
    }
    if (result.exitCode == 0) return null;
    return 'dart pub global activate failed (exit ${result.exitCode})';
  }
}

/// Updates a standalone release binary.
///
/// Fails closed: the archive is only handed to [BinarySwap] when the release
/// carries a `.sha256` file and the downloaded bytes match it. Anything else
/// (missing or malformed checksum, download error, mismatch) keeps the
/// running binary untouched.
class BinaryInstaller implements SelfInstaller {
  /// Creates an installer for the release [asset] of this platform.
  BinaryInstaller({
    required String asset,
    required BinarySwap swap,
    Downloader? download,
  }) : _asset = asset,
       _swap = swap,
       _download = download ?? httpsDownload;

  final String _asset;
  final BinarySwap _swap;
  final Downloader _download;

  @override
  Future<String?> install(Version target) async {
    final checksumBytes = await _download(
      releaseAssetUri(target, '$_asset.sha256'),
      maxBytes: 1024,
    );
    if (checksumBytes == null) {
      return 'no checksum file in release v$target';
    }
    final expected = parseSha256File(
      utf8.decode(checksumBytes, allowMalformed: true),
    );
    if (expected == null) return 'malformed checksum file in release v$target';

    final archive = await _download(
      releaseAssetUri(target, _asset),
      maxBytes: kMaxArchiveBytes,
    );
    if (archive == null) return 'download of $_asset failed';
    if (!sha256Matches(archive, expected)) {
      return 'checksum mismatch for $_asset, download discarded';
    }
    return _swap(archive, target);
  }
}

/// Downloads [uri] over HTTPS only, following redirects only to HTTPS, and
/// stops at [maxBytes]. Returns `null` on any error.
Future<List<int>?> httpsDownload(Uri uri, {required int maxBytes}) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
  try {
    // Redirects are followed by hand: the automatic follower would already
    // have sent the request over plain HTTP before any check could run.
    var target = uri;
    HttpClientResponse? response;
    for (var hop = 0; hop <= 5; hop++) {
      if (target.scheme != 'https') return null;
      final request = await client
          .getUrl(target)
          .timeout(const Duration(seconds: 15));
      request.followRedirects = false;
      final current = await request.close().timeout(
        const Duration(seconds: 30),
      );
      final location = current.headers.value(HttpHeaders.locationHeader);
      if (current.isRedirect && location != null) {
        await current.drain<void>();
        target = target.resolve(location);
        continue;
      }
      response = current;
      break;
    }
    if (response == null) return null; // too many redirects
    if (response.statusCode != HttpStatus.ok ||
        response.contentLength > maxBytes) {
      await response.drain<void>();
      return null;
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response.timeout(const Duration(seconds: 60))) {
      builder.add(chunk);
      if (builder.length > maxBytes) return null;
    }
    return builder.takeBytes();
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// The real [BinarySwap]: unpacks `loam` next to [executablePath], checks that
/// it reports the expected version, and renames it over the running binary
/// (atomic on the same filesystem; the running process keeps its old inode).
BinarySwap nativeBinarySwap(
  String executablePath, {
  ProcessRunner? runProcess,
}) => (archive, target) async {
  final run = runProcess ?? boundedRunner(kProbeTimeout);
  final dir = p.dirname(executablePath);
  Directory work;
  try {
    work = Directory(dir).createTempSync('.loam-update-');
  } on FileSystemException {
    return 'cannot write to $dir';
  }
  try {
    final archiveFile = File(p.join(work.path, 'loam.tar.gz'))
      ..writeAsBytesSync(archive);
    final untar = await run('tar', [
      '-xzf',
      archiveFile.path,
      '-C',
      work.path,
      'loam',
    ]);
    final candidate = p.join(work.path, 'loam');
    if (untar.exitCode != 0 ||
        FileSystemEntity.typeSync(candidate, followLinks: false) !=
            FileSystemEntityType.file) {
      return 'release archive does not contain the loam binary';
    }
    await run('chmod', ['755', candidate]);
    final probe = await run(candidate, ['--version']);
    if (parseVersionOutput('${probe.stdout}') != target) {
      return 'downloaded binary does not report version $target';
    }
    File(candidate).renameSync(executablePath);
    return null;
  } on TimeoutException {
    return 'unpacking or probing the new binary timed out';
  } on Object catch (e) {
    return 'replacing the binary failed: ${e.runtimeType}';
  } finally {
    try {
      work.deleteSync(recursive: true);
      // loam-ignore: slop-empty-catch – a leftover temp dir is harmless; the next update creates a fresh one.
    } on FileSystemException {
      // A leftover temp dir is harmless; the next update uses a fresh one.
    }
  }
};

/// The background half of the auto-update: fetches the latest version,
/// records it, and — when an installer is given — installs a newer stable
/// release and records the outcome for the next foreground run.
class UpdateWorker {
  /// Creates a worker. [installer] `null` means check only (notify mode).
  UpdateWorker({
    required Version current,
    required List<String> currentRuleIds,
    required UpdateStateStore store,
    required LatestVersionFetcher fetcher,
    SelfInstaller? installer,
    DateTime Function()? now,
  }) : _current = current,
       _currentRuleIds = currentRuleIds,
       _store = store,
       _fetcher = fetcher,
       _installer = installer,
       _now = now ?? (() => DateTime.now().toUtc());

  final Version _current;
  final List<String> _currentRuleIds;
  final UpdateStateStore _store;
  final LatestVersionFetcher _fetcher;
  final SelfInstaller? _installer;
  final DateTime Function() _now;

  /// Runs one check (and install). Never throws.
  Future<void> run() async {
    final latest = await _fetcher.fetchLatest('loam');
    _store.update((s) => s.copyWith(latest: latest, checkedAt: _now()));

    final installer = _installer;
    if (installer == null || latest == null) return;
    if (!isNewerStable(_current, latest)) return;

    String? reason;
    try {
      reason = await installer.install(latest);
    } on Object catch (e) {
      reason = 'unexpected error: ${e.runtimeType}';
    }
    final outcome = UpdateOutcome(
      kind: reason == null
          ? UpdateOutcomeKind.applied
          : UpdateOutcomeKind.failed,
      from: _current,
      to: latest,
      reason: reason,
      previousRuleIds: _currentRuleIds,
    );
    _store.update((s) => s.copyWith(outcome: outcome));
  }
}

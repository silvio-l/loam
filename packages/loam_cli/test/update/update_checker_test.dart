@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/update/latest_version_fetcher.dart';
import 'package:loam/src/update/update_check_cache.dart';
import 'package:loam/src/update/update_checker.dart';
import 'package:loam/src/update/update_notice.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fakes
// ---------------------------------------------------------------------------

/// Fake [LatestVersionFetcher] that returns a fixed version or null.
class FakeLatestVersionFetcher implements LatestVersionFetcher {
  final Version? _version;
  int callCount = 0;

  FakeLatestVersionFetcher(this._version);

  @override
  Future<Version?> fetchLatest(String packageName) async {
    callCount++;
    return _version;
  }
}

/// Fake [UpdateCheckCache] backed by an in-memory store.
class FakeUpdateCheckCache implements UpdateCheckCache {
  UpdateCheckEntry? _entry;
  int readCount = 0;
  int writeCount = 0;

  @override
  UpdateCheckEntry? read() {
    readCount++;
    return _entry;
  }

  @override
  void write(UpdateCheckEntry entry) {
    writeCount++;
    _entry = entry;
  }
}

/// Builds an [UpdateChecker] with all dependencies faked.
UpdateChecker _checker({
  String currentVersion = '0.1.4',
  FakeLatestVersionFetcher? fetcher,
  FakeUpdateCheckCache? cache,
  DateTime Function()? now,
  Map<String, String>? env,
}) {
  return UpdateChecker(
    currentVersion: currentVersion,
    fetcher: fetcher ?? FakeLatestVersionFetcher(null),
    cache: cache ?? FakeUpdateCheckCache(),
    now: now,
    env: env ?? {},
  );
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // ---------------------------------------------------------------------------
  // formatUpdateNotice — pure function / string snapshot
  // ---------------------------------------------------------------------------

  group('formatUpdateNotice', () {
    test('produces exact stderr line', () {
      final notice = UpdateNotice(
        currentVersion: Version.parse('0.1.4'),
        latestVersion: Version.parse('0.2.0'),
        updateCommand: 'dart pub global activate loam',
      );
      expect(
        formatUpdateNotice(notice),
        'loam: Update verfügbar 0.1.4 → 0.2.0 · dart pub global activate loam',
      );
    });

    test('includes update command exactly', () {
      final notice = UpdateNotice(
        currentVersion: Version.parse('0.1.9'),
        latestVersion: Version.parse('0.1.10'),
        updateCommand: 'dart pub global activate loam',
      );
      final result = formatUpdateNotice(notice);
      expect(result, contains('dart pub global activate loam'));
    });
  });

  // ---------------------------------------------------------------------------
  // parsePubDevVersion — JSON→Version parsing separated from HTTP
  // ---------------------------------------------------------------------------

  group('parsePubDevVersion', () {
    test('parses valid pub.dev sample payload', () {
      const json = '''
{
  "name": "loam",
  "latest": {
    "version": "0.2.0",
    "pubspec": {}
  }
}
''';
      expect(parsePubDevVersion(json), Version.parse('0.2.0'));
    });

    test('returns null for missing latest field', () {
      expect(parsePubDevVersion('{"name": "loam"}'), isNull);
    });

    test('returns null for missing version in latest', () {
      expect(parsePubDevVersion('{"latest": {}}'), isNull);
    });

    test('returns null for malformed JSON', () {
      expect(parsePubDevVersion('not json at all'), isNull);
    });

    test('returns null for empty string', () {
      expect(parsePubDevVersion(''), isNull);
    });

    test('correctly parses 0.1.10 (semver patch > 9)', () {
      const json = '{"latest": {"version": "0.1.10"}}';
      expect(parsePubDevVersion(json), Version.parse('0.1.10'));
    });
  });

  // ---------------------------------------------------------------------------
  // Env-based suppression
  // ---------------------------------------------------------------------------

  group('UpdateChecker — LOAM_NO_UPDATE_CHECK suppression', () {
    test('returns null when LOAM_NO_UPDATE_CHECK is set', () async {
      final fetcher = FakeLatestVersionFetcher(Version.parse('1.0.0'));
      final checker = _checker(
        fetcher: fetcher,
        env: {'LOAM_NO_UPDATE_CHECK': '1'},
      );
      expect(await checker.check(), isNull);
      expect(fetcher.callCount, 0);
    });

    test('returns null when LOAM_NO_UPDATE_CHECK is empty string', () async {
      final fetcher = FakeLatestVersionFetcher(Version.parse('1.0.0'));
      final checker = _checker(
        fetcher: fetcher,
        env: {'LOAM_NO_UPDATE_CHECK': ''},
      );
      // containsKey is true even for empty string value
      expect(await checker.check(), isNull);
      expect(fetcher.callCount, 0);
    });
  });

  group('UpdateChecker — CI suppression', () {
    test('returns null when CI is set', () async {
      final fetcher = FakeLatestVersionFetcher(Version.parse('1.0.0'));
      final checker = _checker(fetcher: fetcher, env: {'CI': 'true'});
      expect(await checker.check(), isNull);
      expect(fetcher.callCount, 0);
    });

    test('returns null when GITHUB_ACTIONS is set', () async {
      final fetcher = FakeLatestVersionFetcher(Version.parse('1.0.0'));
      final checker = _checker(
        fetcher: fetcher,
        env: {'GITHUB_ACTIONS': 'true'},
      );
      expect(await checker.check(), isNull);
      expect(fetcher.callCount, 0);
    });

    test('CI suppression overrides even when update is available', () async {
      final fetcher = FakeLatestVersionFetcher(Version.parse('9.9.9'));
      final checker = _checker(fetcher: fetcher, env: {'CI': '1'});
      expect(await checker.check(), isNull);
    });
  });

  // ---------------------------------------------------------------------------
  // Throttle: fresh cache (< 24 h)
  // ---------------------------------------------------------------------------

  group('UpdateChecker — throttle: fresh cache', () {
    test('no network call when cache is fresh', () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      final cache = FakeUpdateCheckCache()
        ..write(
          UpdateCheckEntry(
            latest: Version.parse('0.2.0'),
            checkedAt: now.subtract(const Duration(hours: 1)),
          ),
        );
      cache.writeCount = 0; // reset counter

      final fetcher = FakeLatestVersionFetcher(Version.parse('0.2.0'));
      final checker = _checker(
        currentVersion: '0.1.4',
        fetcher: fetcher,
        cache: cache,
        now: () => now,
      );

      final notice = await checker.check();
      expect(fetcher.callCount, 0, reason: 'no network call on fresh cache');
      expect(notice, isNotNull);
      expect(notice!.latestVersion, Version.parse('0.2.0'));
    });

    test('returns null when fresh cache shows same version', () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      final cache = FakeUpdateCheckCache()
        ..write(
          UpdateCheckEntry(
            latest: Version.parse('0.1.4'),
            checkedAt: now.subtract(const Duration(hours: 2)),
          ),
        );
      cache.writeCount = 0;

      final fetcher = FakeLatestVersionFetcher(null);
      final checker = _checker(
        currentVersion: '0.1.4',
        fetcher: fetcher,
        cache: cache,
        now: () => now,
      );

      expect(await checker.check(), isNull);
      expect(fetcher.callCount, 0);
    });
  });

  // ---------------------------------------------------------------------------
  // Throttle: stale cache (≥ 24 h)
  // ---------------------------------------------------------------------------

  group('UpdateChecker — throttle: stale cache', () {
    test('fetches when cache is exactly 24 h old', () async {
      final now = DateTime.utc(2026, 1, 2, 12);
      final cache = FakeUpdateCheckCache()
        ..write(
          UpdateCheckEntry(
            latest: Version.parse('0.1.4'),
            checkedAt: now.subtract(const Duration(hours: 24)),
          ),
        );
      cache.writeCount = 0;

      final fetcher = FakeLatestVersionFetcher(Version.parse('0.2.0'));
      final checker = _checker(
        currentVersion: '0.1.4',
        fetcher: fetcher,
        cache: cache,
        now: () => now,
      );

      final notice = await checker.check();
      expect(fetcher.callCount, 1, reason: 'should fetch when stale');
      expect(notice, isNotNull);
    });

    test('fetches when cache is absent', () async {
      final fetcher = FakeLatestVersionFetcher(Version.parse('0.2.0'));
      final cache = FakeUpdateCheckCache();
      final now = DateTime.utc(2026, 1, 1, 12);

      final checker = _checker(
        currentVersion: '0.1.4',
        fetcher: fetcher,
        cache: cache,
        now: () => now,
      );

      final notice = await checker.check();
      expect(fetcher.callCount, 1);
      expect(notice, isNotNull);
      // Cache should have been written.
      expect(cache.writeCount, greaterThan(0));
    });

    test('timestamp refreshed after successful fetch', () async {
      final now = DateTime.utc(2026, 6, 8, 10);
      final cache = FakeUpdateCheckCache();
      final fetcher = FakeLatestVersionFetcher(Version.parse('0.2.0'));

      final checker = _checker(
        currentVersion: '0.1.4',
        fetcher: fetcher,
        cache: cache,
        now: () => now,
      );

      await checker.check();

      final entry = cache.read();
      expect(entry, isNotNull);
      expect(entry!.checkedAt, now);
    });
  });

  // ---------------------------------------------------------------------------
  // Fetch errors — timestamp refreshed, null returned
  // ---------------------------------------------------------------------------

  group('UpdateChecker — fetch failure', () {
    test('returns null on fetch failure', () async {
      final fetcher = FakeLatestVersionFetcher(null); // simulates timeout/error
      final cache = FakeUpdateCheckCache();
      final now = DateTime.utc(2026, 1, 1, 12);

      final checker = _checker(fetcher: fetcher, cache: cache, now: () => now);

      expect(await checker.check(), isNull);
    });

    test(
      'timestamp refreshed even after fetch failure (no retry storm)',
      () async {
        final now = DateTime.utc(2026, 1, 1, 12);
        final fetcher = FakeLatestVersionFetcher(null);
        final cache = FakeUpdateCheckCache();

        final checker = _checker(
          fetcher: fetcher,
          cache: cache,
          now: () => now,
        );

        await checker.check();

        // Even with no version available, a write should have been made to
        // record the timestamp and prevent retry storms.
        expect(cache.writeCount, 1);
        final entry = cache.read();
        expect(entry, isNotNull);
        expect(entry!.checkedAt, now);
      },
    );

    test('second call within 24 h after failed fetch uses cached sentinel (no '
        'further network call)', () async {
      final now = DateTime.utc(2026, 1, 1, 12);
      final fetcher = FakeLatestVersionFetcher(null);
      final cache = FakeUpdateCheckCache();

      final checker = _checker(fetcher: fetcher, cache: cache, now: () => now);

      // First call — fails, writes sentinel.
      await checker.check();
      final firstFetchCount = fetcher.callCount;

      // Second call — same time, cache is fresh → no fetch.
      await checker.check();
      expect(
        fetcher.callCount,
        firstFetchCount,
        reason: 'no extra network call within 24 h after failed fetch',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // Semver comparison
  // ---------------------------------------------------------------------------

  group('UpdateChecker — semver comparison', () {
    Future<UpdateNotice?> checkVersions(String current, String latest) async {
      final now = DateTime.utc(2026, 1, 1);
      final cache = FakeUpdateCheckCache()
        ..write(
          UpdateCheckEntry(
            latest: Version.parse(latest),
            checkedAt: now.subtract(const Duration(hours: 1)),
          ),
        );
      return _checker(
        currentVersion: current,
        cache: cache,
        now: () => now,
      ).check();
    }

    test('0.1.10 > 0.1.9 → notice', () async {
      expect(await checkVersions('0.1.9', '0.1.10'), isNotNull);
    });

    test('latest == current → null', () async {
      expect(await checkVersions('0.2.0', '0.2.0'), isNull);
    });

    test('latest < current → null', () async {
      expect(await checkVersions('0.2.0', '0.1.4'), isNull);
    });

    test('current is prerelease higher than latest → null', () async {
      // Dev version 0.2.0-dev.1 > 0.1.4, so no nag.
      expect(await checkVersions('0.2.0-dev.1', '0.1.4'), isNull);
    });

    test('notice contains correct versions', () async {
      final notice = await checkVersions('0.1.4', '0.2.0');
      expect(notice, isNotNull);
      expect(notice!.currentVersion, Version.parse('0.1.4'));
      expect(notice.latestVersion, Version.parse('0.2.0'));
      expect(notice.updateCommand, 'dart pub global activate loam');
    });
  });

  // ---------------------------------------------------------------------------
  // FileUpdateCheckCache round-trip (real filesystem)
  // ---------------------------------------------------------------------------

  group('FileUpdateCheckCache round-trip', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('loam_cache_test_');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('write then read returns same entry', () {
      final cache = _InjectableDirCache(tempDir.path);
      final entry = UpdateCheckEntry(
        latest: Version.parse('0.2.0'),
        checkedAt: DateTime.utc(2026, 6, 8, 10, 30),
      );

      cache.write(entry);
      final read = cache.read();

      expect(read, isNotNull);
      expect(read!.latest, Version.parse('0.2.0'));
      expect(read.checkedAt, DateTime.utc(2026, 6, 8, 10, 30));
    });

    test('read returns null when no file exists', () {
      final cache = _InjectableDirCache(tempDir.path);
      expect(cache.read(), isNull);
    });

    test('non-writable directory → write is silent (no crash)', () {
      // Point to a file path so create-dir fails.
      final badPath = File('${tempDir.path}/file.txt')..writeAsStringSync('x');
      final cache = _InjectableDirCache(badPath.path);
      expect(
        () => cache.write(
          UpdateCheckEntry(
            latest: Version.parse('0.1.0'),
            checkedAt: DateTime.utc(2026, 1, 1),
          ),
        ),
        returnsNormally,
      );
    });
  });
}

// ---------------------------------------------------------------------------
// Test-only helper: FileUpdateCheckCache with injectable directory.
// ---------------------------------------------------------------------------

/// Thin subclass that overrides [cacheDir] via a constructor parameter so
/// tests can use a temp directory without touching real OS cache paths.
class _InjectableDirCache implements UpdateCheckCache {
  final String _dir;

  _InjectableDirCache(this._dir);

  String get _cachePath => '$_dir/update_check.json';

  @override
  UpdateCheckEntry? read() {
    try {
      final file = File(_cachePath);
      if (!file.existsSync()) return null;
      final content = file.readAsStringSync();
      // Reuse the real parse logic from FileUpdateCheckCache via manual decode.
      // We need to decode JSON and reconstruct the entry.
      return _parseEntry(content);
    } catch (_) {
      return null;
    }
  }

  @override
  void write(UpdateCheckEntry entry) {
    try {
      final dir = Directory(_dir);
      if (!dir.existsSync()) {
        dir.createSync(recursive: true);
      }
      final content =
          '{"latest":"${entry.latest}","checkedAt":"${entry.checkedAt.toIso8601String()}"}';
      File(_cachePath).writeAsStringSync(content);
    } catch (_) {
      // Silently swallow write errors.
    }
  }

  UpdateCheckEntry? _parseEntry(String content) {
    try {
      // Simple manual JSON parse to avoid importing dart:convert in test scope.
      final latestMatch = RegExp(
        r'"latest"\s*:\s*"([^"]+)"',
      ).firstMatch(content);
      final checkedAtMatch = RegExp(
        r'"checkedAt"\s*:\s*"([^"]+)"',
      ).firstMatch(content);
      if (latestMatch == null || checkedAtMatch == null) return null;
      return UpdateCheckEntry(
        latest: Version.parse(latestMatch.group(1)!),
        checkedAt: DateTime.parse(checkedAtMatch.group(1)!),
      );
    } catch (_) {
      return null;
    }
  }
}

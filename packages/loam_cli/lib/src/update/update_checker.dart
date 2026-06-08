import 'dart:io';

import 'package:pub_semver/pub_semver.dart';

import 'latest_version_fetcher.dart';
import 'update_check_cache.dart';
import 'update_notice.dart';

/// Checks whether a newer version of loam is available on pub.dev.
///
/// **Deep module contract:** the single public method [check] encapsulates all
/// update-check logic. All side-effects (network, filesystem, clock) are
/// injected via constructor parameters so that the logic is fully testable
/// without real I/O.
///
/// Decision matrix (applied in order):
/// 1. `LOAM_NO_UPDATE_CHECK` set → returns `null` immediately.
/// 2. `CI` or `GITHUB_ACTIONS` set → returns `null` (CI is always silent).
/// 3. Cache is fresh (< 24 h) → compares against cached version, no network.
/// 4. Cache is stale / absent → fetches from pub.dev (2 s timeout).
///    Success: writes `latest` + timestamp. Error: writes timestamp only
///    (no retry storm), returns `null`.
/// 5. Returns [UpdateNotice] only when `latest > current`; `null` otherwise.
class UpdateChecker {
  /// The name of the package to check on pub.dev.
  static const _packageName = 'loam';

  /// The update command shown to the user.
  static const _updateCommand = 'dart pub global activate loam';

  /// The throttle duration — checks run at most once every 24 hours.
  static const _throttle = Duration(hours: 24);

  final String _currentVersion;
  final LatestVersionFetcher _fetcher;
  final UpdateCheckCache _cache;
  final DateTime Function() _now;

  /// Environment variables used for suppression decisions.
  ///
  /// Defaults to [Platform.environment]. Injected for testability.
  final Map<String, String> _env;

  /// Creates an [UpdateChecker].
  ///
  /// - [currentVersion]: the installed version string (e.g. `'0.1.4'`).
  /// - [fetcher]: used to retrieve the latest version from pub.dev.
  /// - [cache]: used to persist and retrieve the throttle timestamp.
  /// - [now]: clock function, injected for throttle tests.
  /// - [env]: environment variable map, defaults to [Platform.environment].
  UpdateChecker({
    required String currentVersion,
    LatestVersionFetcher? fetcher,
    UpdateCheckCache? cache,
    DateTime Function()? now,
    Map<String, String>? env,
  }) : _currentVersion = currentVersion,
       _fetcher = fetcher ?? const PubDevLatestVersionFetcher(),
       _cache = cache ?? const FileUpdateCheckCache(),
       _now = now ?? (() => DateTime.now().toUtc()),
       _env = env ?? Platform.environment;

  /// Checks for an available update and returns an [UpdateNotice] when one is
  /// found.
  ///
  /// Returns `null` when:
  /// - Suppressed by env vars (`LOAM_NO_UPDATE_CHECK`, `CI`, `GITHUB_ACTIONS`).
  /// - The installed version is already the latest (or newer / prerelease).
  /// - Any network/parse/filesystem error occurs.
  ///
  /// Never throws — all errors are swallowed internally.
  Future<UpdateNotice?> check() async {
    try {
      return await _check();
    } catch (_) {
      return null;
    }
  }

  Future<UpdateNotice?> _check() async {
    // 1. Hard env opt-out.
    if (_env.containsKey('LOAM_NO_UPDATE_CHECK')) return null;

    // 2. CI silence.
    if (_env.containsKey('CI') || _env.containsKey('GITHUB_ACTIONS')) {
      return null;
    }

    final current = Version.parse(_currentVersion);
    final now = _now();

    // 3. Throttle: try to use cache if fresh.
    final cached = _cache.read();
    Version? latest;

    if (cached != null && now.difference(cached.checkedAt) < _throttle) {
      // Cache is fresh — use cached version, no network call.
      latest = cached.latest;
    } else {
      // 4. Cache is stale or absent — fetch from pub.dev.
      final fetched = await _fetcher.fetchLatest(_packageName);

      // Always refresh the timestamp to avoid retry storms, even on failure.
      final latestToCache = fetched ?? cached?.latest;
      if (latestToCache != null) {
        _cache.write(UpdateCheckEntry(latest: latestToCache, checkedAt: now));
      } else {
        // Write a sentinel entry with an epoch version so we still record the
        // timestamp (prevents retry storms when pub.dev is unreachable).
        _cache.write(UpdateCheckEntry(latest: Version.none, checkedAt: now));
      }

      if (fetched == null) return null;
      latest = fetched;
    }

    // 5. Semver comparison: return notice only when latest > current.
    if (latest <= current) return null;

    return UpdateNotice(
      currentVersion: current,
      latestVersion: latest,
      updateCommand: _updateCommand,
    );
  }
}

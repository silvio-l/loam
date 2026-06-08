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
/// 1. `noUpdateCheckFlag` is `true` (CLI `--no-update-check`) → returns `null`.
/// 2. `LOAM_NO_UPDATE_CHECK` set (env) → returns `null` immediately.
/// 3. `CI` or `GITHUB_ACTIONS` set → returns `null` (CI is always silent;
///    not overridable).
/// 4. `configUpdateCheck` is `false` (loam.yaml opt-out) → returns `null`.
/// 5. Cache is fresh (< 24 h) → compares against cached version, no network.
/// 6. Cache is stale / absent → fetches from pub.dev (2 s timeout).
///    Success: writes `latest` + timestamp. Error: writes timestamp only
///    (no retry storm), returns `null`.
/// 7. Returns [UpdateNotice] only when `latest > current`; `null` otherwise.
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
  /// The full opt-out precedence chain is applied before any network/cache I/O:
  /// `--no-update-check` (CLI via [noUpdateCheckFlag]) >
  /// `LOAM_NO_UPDATE_CHECK` (env) >
  /// CI/GITHUB_ACTIONS (env, non-overridable) >
  /// `update_check: false` (loam.yaml via [configUpdateCheck]) >
  /// default (on).
  ///
  /// Returns `null` when:
  /// - Suppressed by any opt-out in the precedence chain.
  /// - The installed version is already the latest (or newer / prerelease).
  /// - Any network/parse/filesystem error occurs.
  ///
  /// Never throws — all errors are swallowed internally.
  ///
  /// - [noUpdateCheckFlag]: `true` when the user passed `--no-update-check` on
  ///   the CLI (highest-priority opt-out, per-run only).
  /// - [configUpdateCheck]: the `update_check` value from `loam.yaml`
  ///   (`false` = repo-wide opt-out). Defaults to `true` (no config opt-out).
  Future<UpdateNotice?> check({
    bool noUpdateCheckFlag = false,
    bool configUpdateCheck = true,
  }) async {
    try {
      return await _check(
        noUpdateCheckFlag: noUpdateCheckFlag,
        configUpdateCheck: configUpdateCheck,
      );
    } catch (_) {
      return null;
    }
  }

  Future<UpdateNotice?> _check({
    required bool noUpdateCheckFlag,
    required bool configUpdateCheck,
  }) async {
    // 1. CLI flag opt-out (highest priority, per-run).
    if (noUpdateCheckFlag) return null;

    // 2. Hard env opt-out.
    if (_env.containsKey('LOAM_NO_UPDATE_CHECK')) return null;

    // 3. CI silence (non-overridable).
    if (_env.containsKey('CI') || _env.containsKey('GITHUB_ACTIONS')) {
      return null;
    }

    // 4. Config-layer opt-out (loam.yaml: update_check: false).
    if (!configUpdateCheck) return null;

    final current = Version.parse(_currentVersion);
    final now = _now();

    // 5. Throttle: try to use cache if fresh.
    final cached = _cache.read();
    Version? latest;

    if (cached != null && now.difference(cached.checkedAt) < _throttle) {
      // Cache is fresh — use cached version, no network call.
      latest = cached.latest;
    } else {
      // 6. Cache is stale or absent — fetch from pub.dev.
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

    // 7. Semver comparison: return notice only when latest > current.
    if (latest <= current) return null;

    return UpdateNotice(
      currentVersion: current,
      latestVersion: latest,
      updateCommand: _updateCommand,
    );
  }
}

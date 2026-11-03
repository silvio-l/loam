import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

import 'install_channel.dart';
import 'update_state.dart';

/// What loam may do about updates in this run.
enum UpdateMode {
  /// Nothing: no network, no notice, no install.
  off,

  /// Check in the background and print a notice with the upgrade command.
  notify,

  /// Check and install the newest version in the background.
  auto,
}

/// Checks run at most once per this interval (also after a failed check).
const Duration kUpdateCheckInterval = Duration(hours: 24);

/// Environment variables that mark a CI run. Covers the generic `CI` flag set
/// by most providers plus the providers that only set their own variable.
const List<String> kCiEnvironmentVariables = [
  'CI',
  'CONTINUOUS_INTEGRATION',
  'GITHUB_ACTIONS',
  'GITLAB_CI',
  'BUILDKITE',
  'CIRCLECI',
  'TRAVIS',
  'TF_BUILD',
  'TEAMCITY_VERSION',
  'JENKINS_URL',
  'BITBUCKET_BUILD_NUMBER',
  'CODEBUILD_BUILD_ID',
  'DRONE',
  'APPVEYOR',
];

/// Whether [env] describes a CI run. `CI=false` / `CI=0` count as "not CI".
bool isCiEnvironment(Map<String, String> env) {
  for (final name in kCiEnvironmentVariables) {
    final value = env[name];
    if (value == null) continue;
    final normalized = value.trim().toLowerCase();
    if (normalized == 'false' || normalized == '0') continue;
    return true;
  }
  return false;
}

/// Decides the [UpdateMode] for one run (a pure function).
///
/// Applied in order — the first match wins:
/// 1. `--no-update-check` ([noUpdateCheckFlag]) → off.
/// 2. `LOAM_NO_UPDATE_CHECK` set → off.
/// 3. CI ([isCiEnvironment]) → off. Not overridable: a CI gate must stay
///    reproducible and must never change its own binary.
/// 4. `LOAM_OFFLINE` set → off (no network at all).
/// 5. `update_check: false` ([configUpdateCheck]) → off.
/// 6. `required_version` set ([requiredVersion]) → off. A pinned project is
///    never updated; the pin check itself is [pinViolation].
/// 7. `LOAM_NO_AUTO_UPDATE` set or `auto_update: false` → notify.
/// 8. The install channel cannot update itself safely ([canSelfUpdate]) →
///    notify (Homebrew, source runs, git/path pub installs).
/// 9. Otherwise → auto.
UpdateMode decideUpdateMode({
  required Map<String, String> env,
  bool noUpdateCheckFlag = false,
  bool configUpdateCheck = true,
  bool configAutoUpdate = true,
  VersionConstraint? requiredVersion,
  required bool canSelfUpdate,
}) {
  if (noUpdateCheckFlag) return UpdateMode.off;
  if (env.containsKey('LOAM_NO_UPDATE_CHECK')) return UpdateMode.off;
  if (isCiEnvironment(env)) return UpdateMode.off;
  if (env.containsKey('LOAM_OFFLINE')) return UpdateMode.off;
  if (!configUpdateCheck) return UpdateMode.off;
  if (requiredVersion != null) return UpdateMode.off;
  if (env.containsKey('LOAM_NO_AUTO_UPDATE') || !configAutoUpdate) {
    return UpdateMode.notify;
  }
  return canSelfUpdate ? UpdateMode.auto : UpdateMode.notify;
}

/// Whether the running [current] version violates the project pin.
bool pinViolation(Version current, VersionConstraint? requiredVersion) =>
    requiredVersion != null && !requiredVersion.allows(current);

/// Whether [latest] should replace [current]: strictly newer and stable.
/// Never downgrades and never installs a pre-release.
bool isNewerStable(Version current, Version? latest) =>
    latest != null && !latest.isPreRelease && latest > current;

/// Whether a background check is due at [now] given the last [state].
///
/// Due when never checked, when the interval elapsed, or when the stored
/// timestamp lies in the future (clock moved back) so a skewed clock cannot
/// disable checks forever.
bool isCheckDue(UpdateState state, DateTime now) {
  final checkedAt = state.checkedAt;
  if (checkedAt == null) return true;
  final age = now.difference(checkedAt);
  return age.isNegative || age >= kUpdateCheckInterval;
}

/// Whether a pub-global install came from pub.dev (`source: hosted` for the
/// `loam` package in the global `pubspec.lock`). Git or path activations are
/// developer installs and must not be replaced by the pub.dev release.
bool isHostedPubGlobalLock(String lockContent) {
  try {
    final doc = loadYaml(lockContent);
    if (doc is! YamlMap) return false;
    final packages = doc['packages'];
    if (packages is! YamlMap) return false;
    final loam = packages['loam'];
    return loam is YamlMap && loam['source'] == 'hosted';
  } on Object {
    return false;
  }
}

/// Whether [info]'s channel can install a new version without user action.
///
/// - pub-global: only a pub.dev install ([pubLockContent] is the global
///   `pubspec.lock` of the loam activation, `null` if unreadable).
/// - binary: only an official release build ([isReleaseBinary], the
///   `loam.release_binary` compile-time define) for which a release asset exists on this platform
///   ([hasBinaryAsset]). A locally compiled `dart compile exe` binary is a
///   developer build and must never be replaced by the release binary.
/// - Homebrew: never. Homebrew owns its Cellar and runs `brew update` over all
///   taps plus cleanup on upgrade; a tool must not trigger that unasked.
/// - unknown (source runs): never.
bool canSelfUpdate(
  InstallInfo info, {
  String? pubLockContent,
  bool hasBinaryAsset = false,
  bool isReleaseBinary = false,
}) => switch (info.channel) {
  InstallChannel.pubGlobal =>
    pubLockContent != null && isHostedPubGlobalLock(pubLockContent),
  InstallChannel.binary => isReleaseBinary && hasBinaryAsset,
  InstallChannel.homebrew => false,
  InstallChannel.unknown => false,
};

/// The stderr warning for a running version outside the project pin.
String formatPinViolation(Version current, VersionConstraint requiredVersion) =>
    'loam: this project requires loam $requiredVersion (required_version in '
    'loam.yaml), but $current is running. Install a matching version, e.g. '
    'dart pub global activate loam "$requiredVersion".';

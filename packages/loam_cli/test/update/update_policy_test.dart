import 'package:loam/src/update/install_channel.dart';
import 'package:loam/src/update/update_policy.dart';
import 'package:loam/src/update/update_state.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:test/test.dart';

UpdateMode _mode({
  Map<String, String> env = const {},
  bool flag = false,
  bool updateCheck = true,
  bool autoUpdate = true,
  String? pin,
  bool canSelfUpdate = true,
}) => decideUpdateMode(
  env: env,
  noUpdateCheckFlag: flag,
  configUpdateCheck: updateCheck,
  configAutoUpdate: autoUpdate,
  requiredVersion: pin == null ? null : VersionConstraint.parse(pin),
  canSelfUpdate: canSelfUpdate,
);

void main() {
  group('decideUpdateMode', () {
    test('default with a self-updating channel → auto', () {
      expect(_mode(), UpdateMode.auto);
    });

    test('channel that cannot update itself → notify', () {
      expect(_mode(canSelfUpdate: false), UpdateMode.notify);
    });

    test('pinned project → off, never auto', () {
      expect(_mode(pin: '>=0.1.0 <0.2.0'), UpdateMode.off);
    });

    test('CI → off, even with every opt-in', () {
      expect(_mode(env: {'CI': 'true'}), UpdateMode.off);
      expect(_mode(env: {'GITLAB_CI': 'true'}), UpdateMode.off);
      expect(_mode(env: {'JENKINS_URL': 'http://ci'}), UpdateMode.off);
    });

    test('offline (LOAM_OFFLINE) → off', () {
      expect(_mode(env: {'LOAM_OFFLINE': '1'}), UpdateMode.off);
    });

    test('opt-outs for the whole update path → off', () {
      expect(_mode(flag: true), UpdateMode.off);
      expect(_mode(env: {'LOAM_NO_UPDATE_CHECK': ''}), UpdateMode.off);
      expect(_mode(updateCheck: false), UpdateMode.off);
    });

    test('auto-update opt-outs keep the notice → notify', () {
      expect(_mode(env: {'LOAM_NO_AUTO_UPDATE': '1'}), UpdateMode.notify);
      expect(_mode(autoUpdate: false), UpdateMode.notify);
    });
  });

  group('isCiEnvironment', () {
    test('no CI variable → false', () {
      expect(isCiEnvironment({'HOME': '/x'}), isFalse);
    });

    test('CI=false and CI=0 are not CI', () {
      expect(isCiEnvironment({'CI': 'false'}), isFalse);
      expect(isCiEnvironment({'CI': '0'}), isFalse);
    });

    test('provider-specific variable without CI → true', () {
      expect(isCiEnvironment({'TF_BUILD': 'True'}), isTrue);
    });
  });

  group('pinViolation', () {
    final current = Version.parse('0.2.0');

    test('no pin → never a violation', () {
      expect(pinViolation(current, null), isFalse);
    });

    test('version inside the range → ok', () {
      expect(
        pinViolation(current, VersionConstraint.parse('>=0.2.0 <0.3.0')),
        isFalse,
      );
    });

    test('version outside the range or a different exact pin → violation', () {
      expect(pinViolation(current, VersionConstraint.parse('^0.1.15')), isTrue);
      expect(pinViolation(current, VersionConstraint.parse('0.1.15')), isTrue);
    });
  });

  group('isNewerStable', () {
    final current = Version.parse('0.1.15');

    test('newer stable → true', () {
      expect(isNewerStable(current, Version.parse('0.1.16')), isTrue);
    });

    test('same, older, unknown or pre-release → false (never downgrade)', () {
      expect(isNewerStable(current, Version.parse('0.1.15')), isFalse);
      expect(isNewerStable(current, Version.parse('0.1.14')), isFalse);
      expect(isNewerStable(current, null), isFalse);
      expect(isNewerStable(current, Version.parse('0.2.0-dev.1')), isFalse);
    });
  });

  group('isCheckDue', () {
    final now = DateTime.utc(2026, 11, 3, 12);

    test('never checked → due', () {
      expect(isCheckDue(UpdateState.empty, now), isTrue);
    });

    test('checked within the interval → not due', () {
      final state = UpdateState(
        checkedAt: now.subtract(const Duration(hours: 23)),
      );
      expect(isCheckDue(state, now), isFalse);
    });

    test('interval elapsed → due', () {
      final state = UpdateState(checkedAt: now.subtract(kUpdateCheckInterval));
      expect(isCheckDue(state, now), isTrue);
    });

    test('timestamp in the future (clock moved back) → due', () {
      final state = UpdateState(checkedAt: now.add(const Duration(days: 3)));
      expect(isCheckDue(state, now), isTrue);
    });
  });

  group('canSelfUpdate per channel', () {
    const hostedLock = '''
packages:
  loam:
    dependency: "direct main"
    description:
      name: loam
      url: "https://pub.dev"
    source: hosted
    version: "0.1.15"
''';
    const gitLock = '''
packages:
  loam:
    dependency: "direct main"
    description:
      path: packages/loam_cli
      ref: dev
      url: "https://github.com/silvio-l/loam.git"
    source: git
    version: "0.1.15"
''';
    InstallInfo info(InstallChannel c) =>
        InstallInfo(channel: c, executablePath: '/x');

    test('pub-global from pub.dev → true', () {
      expect(
        canSelfUpdate(
          info(InstallChannel.pubGlobal),
          pubLockContent: hostedLock,
        ),
        isTrue,
      );
    });

    test('pub-global from git, or unreadable lock → false', () {
      expect(
        canSelfUpdate(info(InstallChannel.pubGlobal), pubLockContent: gitLock),
        isFalse,
      );
      expect(canSelfUpdate(info(InstallChannel.pubGlobal)), isFalse);
      expect(isHostedPubGlobalLock('not: [yaml'), isFalse);
    });

    test('binary only as a release build with an asset for this platform', () {
      expect(
        canSelfUpdate(
          info(InstallChannel.binary),
          hasBinaryAsset: true,
          isReleaseBinary: true,
        ),
        isTrue,
      );
      expect(
        canSelfUpdate(info(InstallChannel.binary), isReleaseBinary: true),
        isFalse,
      );
    });

    test('a locally compiled binary never replaces itself', () {
      expect(
        canSelfUpdate(info(InstallChannel.binary), hasBinaryAsset: true),
        isFalse,
      );
    });

    test('Homebrew and source runs never update themselves', () {
      expect(
        canSelfUpdate(
          info(InstallChannel.homebrew),
          hasBinaryAsset: true,
          isReleaseBinary: true,
        ),
        isFalse,
      );
      expect(
        canSelfUpdate(
          info(InstallChannel.unknown),
          pubLockContent: hostedLock,
          hasBinaryAsset: true,
          isReleaseBinary: true,
        ),
        isFalse,
      );
    });
  });
}

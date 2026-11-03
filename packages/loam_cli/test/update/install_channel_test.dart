import 'package:loam/src/update/install_channel.dart';
import 'package:test/test.dart';

void main() {
  group('InstallInfo.fromExecutablePath — compiled executable', () {
    test('Homebrew Cellar (macOS, Intel, Linuxbrew) → homebrew', () {
      for (final path in [
        '/opt/homebrew/Cellar/loam/0.1.7/bin/loam',
        '/usr/local/Cellar/loam/0.1.7/bin/loam',
        '/home/linuxbrew/.linuxbrew/Cellar/loam/0.1.7/bin/loam',
      ]) {
        expect(
          InstallInfo.fromExecutablePath(path).channel,
          InstallChannel.homebrew,
          reason: path,
        );
      }
    });

    test('a standalone loam binary → binary', () {
      expect(
        InstallInfo.fromExecutablePath('/opt/loam/bin/loam').channel,
        InstallChannel.binary,
      );
    });

    test('a `cellar` substring that is not a path segment → binary', () {
      expect(
        InstallInfo.fromExecutablePath('/home/mycellar/loam').channel,
        InstallChannel.binary,
      );
    });
  });

  group('InstallInfo.fromExecutablePath — Dart VM runs', () {
    test('pub-global snapshot → pubGlobal, path is the snapshot', () {
      const snapshot =
          '/Users/x/.pub-cache/global_packages/loam/bin/loam.dart-3.13.7.snapshot';
      final info = InstallInfo.fromExecutablePath(
        '/usr/lib/dart/bin/dart',
        scriptPath: snapshot,
      );
      expect(info.channel, InstallChannel.pubGlobal);
      expect(info.executablePath, snapshot);
    });

    test('Homebrew-installed Dart SDK does not make pub-global look like '
        'Homebrew', () {
      final info = InstallInfo.fromExecutablePath(
        '/opt/homebrew/Cellar/dart/3.13.7/libexec/bin/dart',
        scriptPath:
            '/Users/x/.pub-cache/global_packages/loam/bin/loam.dart-3.13.7.snapshot',
      );
      expect(info.channel, InstallChannel.pubGlobal);
    });

    test('Windows pub cache (global_packages, backslashes) → pubGlobal', () {
      final info = InstallInfo.fromExecutablePath(
        r'C:\dart-sdk\bin\dart.exe',
        scriptPath:
            r'C:\Users\x\AppData\Local\Pub\Cache\global_packages\loam\bin\loam.dart-3.13.7.snapshot',
      );
      expect(info.channel, InstallChannel.pubGlobal);
    });

    test('source run (dart run bin/loam.dart) → unknown', () {
      final info = InstallInfo.fromExecutablePath(
        '/opt/homebrew/Cellar/dart/3.13.7/libexec/bin/dart',
        scriptPath: '/work/loam/packages/loam_cli/bin/loam.dart',
      );
      expect(info.channel, InstallChannel.unknown);
    });
  });

  group('InstallInfo — upgradeCommand per channel', () {
    test('homebrew → `brew upgrade loam`', () {
      expect(
        const InstallInfo(
          channel: InstallChannel.homebrew,
          executablePath: '/x',
        ).upgradeCommand,
        'brew upgrade loam',
      );
    });

    test('pubGlobal → `dart pub global activate loam`', () {
      expect(
        const InstallInfo(
          channel: InstallChannel.pubGlobal,
          executablePath: '/x',
        ).upgradeCommand,
        'dart pub global activate loam',
      );
    });

    test('binary → points to the release page', () {
      expect(
        const InstallInfo(
          channel: InstallChannel.binary,
          executablePath: '/x',
        ).upgradeCommand,
        contains(kReleasesUrl),
      );
    });

    test('unknown → pub.dev fallback command', () {
      expect(
        const InstallInfo(
          channel: InstallChannel.unknown,
          executablePath: '/x',
        ).upgradeCommand,
        'dart pub global activate loam',
      );
    });
  });

  group('InstallInfo — channelLabel', () {
    test('labels are stable and human-readable', () {
      expect(
        const InstallInfo(
          channel: InstallChannel.homebrew,
          executablePath: '/x',
        ).channelLabel,
        'homebrew',
      );
      expect(
        const InstallInfo(
          channel: InstallChannel.pubGlobal,
          executablePath: '/x',
        ).channelLabel,
        'pub-global',
      );
      expect(
        const InstallInfo(
          channel: InstallChannel.unknown,
          executablePath: '/x',
        ).channelLabel,
        'source/unknown',
      );
    });
  });
}

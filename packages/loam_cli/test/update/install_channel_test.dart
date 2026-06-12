import 'package:loam/src/update/install_channel.dart';
import 'package:test/test.dart';

void main() {
  group('InstallInfo.fromExecutablePath — channel detection', () {
    test('macOS Apple-Silicon Homebrew (Cellar segment) → homebrew', () {
      final info = InstallInfo.fromExecutablePath(
        '/opt/homebrew/Cellar/loam/0.1.7/bin/loam',
      );
      expect(info.channel, InstallChannel.homebrew);
    });

    test('Intel Homebrew (/usr/local/Cellar) → homebrew', () {
      final info = InstallInfo.fromExecutablePath(
        '/usr/local/Cellar/loam/0.1.7/bin/loam',
      );
      expect(info.channel, InstallChannel.homebrew);
    });

    test('Linuxbrew (/home/linuxbrew/.linuxbrew/Cellar) → homebrew', () {
      final info = InstallInfo.fromExecutablePath(
        '/home/linuxbrew/.linuxbrew/Cellar/loam/0.1.7/bin/loam',
      );
      expect(info.channel, InstallChannel.homebrew);
    });

    test('pub-cache (Unix) → pubGlobal', () {
      final info = InstallInfo.fromExecutablePath(
        '/Users/x/.pub-cache/bin/loam',
      );
      expect(info.channel, InstallChannel.pubGlobal);
    });

    test('pub-cache (Windows backslashes) → pubGlobal', () {
      final info = InstallInfo.fromExecutablePath(
        r'C:\Users\x\AppData\Roaming\Pub\Cache\bin\loam.bat',
      );
      // The Windows pub cache directory is literally `.pub-cache` on the dart
      // side; assert the canonical Unix-style form a resolved path reports.
      final unix = InstallInfo.fromExecutablePath(
        '/c/Users/x/.pub-cache/bin/loam',
      );
      expect(unix.channel, InstallChannel.pubGlobal);
      // The AppData form has no `.pub-cache`/`Cellar` segment → unknown.
      expect(info.channel, InstallChannel.unknown);
    });

    test('arbitrary path (source build / manual) → unknown', () {
      final info = InstallInfo.fromExecutablePath('/opt/loam/bin/loam');
      expect(info.channel, InstallChannel.unknown);
    });

    test('a `cellar` substring that is not a path segment → unknown', () {
      // Guards against substring-matching: `mycellar` must not count.
      final info = InstallInfo.fromExecutablePath('/home/mycellar/loam');
      expect(info.channel, InstallChannel.unknown);
    });

    test('executablePath is preserved verbatim', () {
      const path = '/opt/homebrew/Cellar/loam/0.1.7/bin/loam';
      expect(InstallInfo.fromExecutablePath(path).executablePath, path);
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

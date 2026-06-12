import 'package:loam/src/update/install_channel.dart';
import 'package:loam/src/version.dart';
import 'package:loam/src/version_report.dart';
import 'package:test/test.dart';

void main() {
  group('formatVersionInfo', () {
    test('line 1 is the bare, greppable `loam <version>`', () {
      const info = InstallInfo(
        channel: InstallChannel.homebrew,
        executablePath: '/opt/homebrew/Cellar/loam/0.1.7/bin/loam',
      );
      final firstLine = formatVersionInfo(info).split('\n').first;
      expect(firstLine, 'loam $loamVersion');
    });

    test('renders the SAME version constant the scan footer uses', () {
      // Contract: `loam --version` and the footer both read `loamVersion`, so
      // they can never disagree. version.dart === pubspec is enforced
      // separately by tool/docs-attest.sh (check_version_sync).
      const info = InstallInfo(
        channel: InstallChannel.unknown,
        executablePath: '/x',
      );
      expect(formatVersionInfo(info), contains(loamVersion));
    });

    test('line 2 names the install channel and executable path', () {
      const info = InstallInfo(
        channel: InstallChannel.homebrew,
        executablePath: '/opt/homebrew/Cellar/loam/0.1.7/bin/loam',
      );
      expect(
        formatVersionInfo(info),
        'loam $loamVersion\n'
        'install: homebrew · /opt/homebrew/Cellar/loam/0.1.7/bin/loam',
      );
    });

    test('surfaces a pub-global install distinctly', () {
      const info = InstallInfo(
        channel: InstallChannel.pubGlobal,
        executablePath: '/Users/x/.pub-cache/bin/loam',
      );
      expect(formatVersionInfo(info), contains('install: pub-global · '));
    });
  });
}

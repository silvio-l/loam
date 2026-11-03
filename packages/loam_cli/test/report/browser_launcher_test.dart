library;

import 'package:loam/src/report/browser_launcher.dart';
import 'package:test/test.dart';

void main() {
  group('browserOpenCommand', () {
    test('macos uses the open command', () {
      expect(
        browserOpenCommand('/tmp/loam-report.html', operatingSystem: 'macos'),
        equals(['open', '/tmp/loam-report.html']),
      );
    });

    test('linux uses xdg-open', () {
      expect(
        browserOpenCommand('/tmp/loam-report.html', operatingSystem: 'linux'),
        equals(['xdg-open', '/tmp/loam-report.html']),
      );
    });

    test('windows hands the path to the shell, never through cmd', () {
      // `&` and `^` are cmd syntax: through `cmd /c start` the path would be
      // cut at `&` and the rest run as a command.
      const path = r'C:\a&b^c\loam-report.html';
      final command = browserOpenCommand(path, operatingSystem: 'windows')!;
      expect(command.first, isNot(anyOf('cmd', 'cmd.exe')));
      expect(
        command,
        equals(['rundll32', 'url.dll,FileProtocolHandler', path]),
      );
    });

    test('returns null for an unsupported platform', () {
      expect(
        browserOpenCommand('/tmp/loam-report.html', operatingSystem: 'fuchsia'),
        isNull,
      );
    });
  });

  group('shouldOpenBrowser', () {
    test('opens when interactive, no flag, no CI', () {
      expect(
        shouldOpenBrowser(
          isTty: true,
          noOpenFlag: false,
          environment: const {},
        ),
        isTrue,
      );
    });

    test('never opens when --no-open was passed', () {
      expect(
        shouldOpenBrowser(isTty: true, noOpenFlag: true, environment: const {}),
        isFalse,
      );
    });

    test('never opens when not attached to a terminal (pipe/redirect)', () {
      expect(
        shouldOpenBrowser(
          isTty: false,
          noOpenFlag: false,
          environment: const {},
        ),
        isFalse,
      );
    });

    test('never opens under CI even when interactive', () {
      expect(
        shouldOpenBrowser(
          isTty: true,
          noOpenFlag: false,
          environment: const {'CI': 'true'},
        ),
        isFalse,
      );
    });

    test('treats an empty CI value as not-CI', () {
      expect(
        shouldOpenBrowser(
          isTty: true,
          noOpenFlag: false,
          environment: const {'CI': ''},
        ),
        isTrue,
      );
    });
  });

  group('defaultHtmlReportFileName', () {
    test('is the predictable loam-report.html', () {
      expect(defaultHtmlReportFileName, equals('loam-report.html'));
    });
  });
}

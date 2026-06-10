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

    test('windows uses cmd /c start with an empty title slot', () {
      expect(
        browserOpenCommand(
          r'C:\tmp\loam-report.html',
          operatingSystem: 'windows',
        ),
        equals(['cmd', '/c', 'start', '', r'C:\tmp\loam-report.html']),
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

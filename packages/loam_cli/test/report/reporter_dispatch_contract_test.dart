@TestOn('vm')
library;

import 'package:loam/src/report/html_reporter.dart';
import 'package:loam/src/report/human_reporter.dart';
import 'package:loam/src/report/json_reporter.dart';
import 'package:loam/src/report/markdown_reporter.dart';
import 'package:loam/src/report/reporter_dispatch.dart';
import 'package:loam/src/report/sarif_reporter.dart';
import 'package:test/test.dart';

/// Dispatch-contract test: explicitly locks down the reporterFor() routing
/// table so that regressions are caught immediately.
///
/// Contract:
///   'human'    → HumanReporter
///   'sarif'    → SarifReporter
///   'json'     → JsonReporter
///   'markdown' → MarkdownReporter
///   'html'     → HtmlReporter
///   unknown    → throws ArgumentError
void main() {
  group('reporterFor dispatch contract', () {
    test('"human" returns HumanReporter', () {
      expect(reporterFor('human'), isA<HumanReporter>());
    });

    test('"sarif" returns SarifReporter', () {
      expect(reporterFor('sarif'), isA<SarifReporter>());
    });

    test('"json" returns JsonReporter', () {
      expect(reporterFor('json'), isA<JsonReporter>());
    });

    test('"markdown" returns MarkdownReporter', () {
      expect(reporterFor('markdown'), isA<MarkdownReporter>());
    });

    test('"html" returns HtmlReporter', () {
      expect(reporterFor('html'), isA<HtmlReporter>());
    });

    test('"html" does not throw (now implemented)', () {
      expect(() => reporterFor('html'), returnsNormally);
    });

    test('unknown format throws ArgumentError', () {
      expect(() => reporterFor('xml'), throwsA(isA<ArgumentError>()));
    });

    test('unknown format ArgumentError names the bad value', () {
      try {
        reporterFor('pdf');
        fail('expected ArgumentError');
      } on ArgumentError catch (e) {
        expect(e.invalidValue, equals('pdf'));
      }
    });

    test('"json" does not throw (was previously not-yet-implemented)', () {
      expect(() => reporterFor('json'), returnsNormally);
    });

    test('"markdown" does not throw (was previously not-yet-implemented)', () {
      expect(() => reporterFor('markdown'), returnsNormally);
    });
  });

  group('FormatNotImplementedError', () {
    test('toString for a constructed instance lists available formats', () {
      // FormatNotImplementedError is no longer triggered by html — but we can
      // construct one directly to verify its toString contract.
      final e = FormatNotImplementedError('xlsx');
      final msg = e.toString();
      expect(msg, contains('xlsx'));
      expect(msg, contains('human'));
      expect(msg, contains('sarif'));
      expect(msg, contains('json'));
      expect(msg, contains('markdown'));
      expect(msg, contains('html'));
    });

    test('format field reflects the constructed format string', () {
      final e = FormatNotImplementedError('xlsx');
      expect(e.format, equals('xlsx'));
    });
  });
}

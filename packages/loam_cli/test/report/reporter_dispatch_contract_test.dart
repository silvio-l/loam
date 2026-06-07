@TestOn('vm')
library;

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
///   'html'     → throws FormatNotImplementedError
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

    test('"html" throws FormatNotImplementedError', () {
      expect(
        () => reporterFor('html'),
        throwsA(isA<FormatNotImplementedError>()),
      );
    });

    test('"html" FormatNotImplementedError message mentions html', () {
      try {
        reporterFor('html');
        fail('expected FormatNotImplementedError');
      } on FormatNotImplementedError catch (e) {
        expect(e.toString(), contains('html'));
      }
    });

    test(
      '"html" FormatNotImplementedError message lists available formats',
      () {
        try {
          reporterFor('html');
          fail('expected FormatNotImplementedError');
        } on FormatNotImplementedError catch (e) {
          final msg = e.toString();
          expect(msg, contains('human'));
          expect(msg, contains('sarif'));
          expect(msg, contains('json'));
          expect(msg, contains('markdown'));
        }
      },
    );

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
    test('format field reflects the requested format', () {
      try {
        reporterFor('html');
        fail('expected FormatNotImplementedError');
      } on FormatNotImplementedError catch (e) {
        expect(e.format, equals('html'));
      }
    });

    test('toString does not mention json as pending', () {
      try {
        reporterFor('html');
        fail('expected FormatNotImplementedError');
      } on FormatNotImplementedError catch (e) {
        // json and markdown are now available — the error must not suggest they are pending
        expect(
          e.toString(),
          isNot(contains('Use --format human or --format sarif')),
        );
      }
    });
  });
}

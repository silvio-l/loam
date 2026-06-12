@TestOn('vm')
library;

import 'dart:convert';

import 'package:loam/src/model/finding.dart';
import 'package:loam/src/report/json_reporter.dart';
import 'package:loam/src/report/reporter.dart';
import 'package:loam/src/report/reporter_dispatch.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Shared fixture helpers (pattern from sarif_reporter_test.dart)
// ---------------------------------------------------------------------------

Finding _finding({
  String ruleId = 'unused-public-exports',
  Severity severity = Severity.warning,
  String filePath = '/project/lib/src/foo.dart',
  int line = 10,
  int? column,
  String message = 'Unused export: Foo',
  String fingerprint = 'abc123',
}) => Finding(
  ruleId: ruleId,
  severity: severity,
  filePath: filePath,
  line: line,
  column: column,
  message: message,
  fingerprint: fingerprint,
);

ReportPayload _payload({
  List<Finding> findings = const [],
  String projectRoot = '/project',
  String rulesetVersion = 'ruleset@abc12345',
  String toolVersion = '0.0.2',
  bool isTty = false,
  int suppressedCount = 0,
  ScanStats? stats,
}) => ReportPayload(
  findings: findings,
  projectRoot: projectRoot,
  rulesetVersion: rulesetVersion,
  toolVersion: toolVersion,
  isTty: isTty,
  suppressedCount: suppressedCount,
  stats: stats,
);

void main() {
  // -------------------------------------------------------------------------
  // AC1: JsonReporter implements Reporter; render is a pure function
  // -------------------------------------------------------------------------
  group('JsonReporter interface', () {
    test('JsonReporter implements Reporter', () {
      final Reporter reporter = const JsonReporter();
      expect(reporter, isA<Reporter>());
    });
  });

  // -------------------------------------------------------------------------
  // AC2: Output is valid JSON with required top-level keys
  // -------------------------------------------------------------------------
  group('Envelope structure', () {
    test('output is parseable JSON', () {
      final output = const JsonReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(() => jsonDecode(output), returnsNormally);
    });

    test('schemaVersion == 3', () {
      final output = const JsonReporter().render(
        _payload(findings: [_finding()]),
      );
      final doc = jsonDecode(output) as Map<String, dynamic>;
      expect(doc['schemaVersion'], equals(3));
    });

    test('summary.suppressed carries the suppressed count', () {
      final doc =
          jsonDecode(const JsonReporter().render(_payload(suppressedCount: 2)))
              as Map<String, dynamic>;
      expect((doc['summary'] as Map)['suppressed'], equals(2));
    });

    test('scan object carries scope stats when present', () {
      final doc =
          jsonDecode(
                const JsonReporter().render(
                  _payload(
                    stats: const ScanStats(
                      filesAnalyzed: 168,
                      libFilesAnalyzed: 50,
                      linesAnalyzed: 18432,
                      rulesRun: ['complexity-hotspots'],
                    ),
                  ),
                ),
              )
              as Map<String, dynamic>;
      final scan = doc['scan'] as Map<String, dynamic>;
      expect(scan['filesAnalyzed'], 168);
      expect(scan['libFilesAnalyzed'], 50);
      expect(scan['linesAnalyzed'], 18432);
      expect(scan['rulesRun'], ['complexity-hotspots']);
    });

    test('scan object omitted when stats absent', () {
      final doc =
          jsonDecode(const JsonReporter().render(_payload()))
              as Map<String, dynamic>;
      expect(doc.containsKey('scan'), isFalse);
    });

    test('tool.name == "loam"', () {
      final output = const JsonReporter().render(
        _payload(findings: [_finding()]),
      );
      final doc = jsonDecode(output) as Map<String, dynamic>;
      expect((doc['tool'] as Map<String, dynamic>)['name'], equals('loam'));
    });

    test('tool.version == toolVersion from payload', () {
      final output = const JsonReporter().render(
        _payload(findings: [_finding()], toolVersion: '1.2.3'),
      );
      final doc = jsonDecode(output) as Map<String, dynamic>;
      expect((doc['tool'] as Map<String, dynamic>)['version'], equals('1.2.3'));
    });

    test('ruleset == rulesetVersion from payload', () {
      final output = const JsonReporter().render(
        _payload(findings: [_finding()], rulesetVersion: 'ruleset@deadbeef'),
      );
      final doc = jsonDecode(output) as Map<String, dynamic>;
      expect(doc['ruleset'], equals('ruleset@deadbeef'));
    });

    test('findings array is present', () {
      final output = const JsonReporter().render(
        _payload(findings: [_finding()]),
      );
      final doc = jsonDecode(output) as Map<String, dynamic>;
      expect(doc['findings'], isA<List<dynamic>>());
    });
  });

  // -------------------------------------------------------------------------
  // AC3: summary always has total + all three severity keys
  // -------------------------------------------------------------------------
  group('Summary block', () {
    test('summary has total, error, warning, info', () {
      final output = const JsonReporter().render(
        _payload(findings: [_finding()]),
      );
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final summary = doc['summary'] as Map<String, dynamic>;
      expect(summary.containsKey('total'), isTrue);
      expect(summary.containsKey('error'), isTrue);
      expect(summary.containsKey('warning'), isTrue);
      expect(summary.containsKey('info'), isTrue);
    });

    test('summary counts are correct for mixed findings', () {
      final findings = [
        _finding(severity: Severity.error, fingerprint: 'fp1'),
        _finding(severity: Severity.warning, fingerprint: 'fp2'),
        _finding(severity: Severity.info, fingerprint: 'fp3'),
        _finding(severity: Severity.warning, fingerprint: 'fp4'),
      ];
      final output = const JsonReporter().render(_payload(findings: findings));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final summary = doc['summary'] as Map<String, dynamic>;
      expect(summary['total'], equals(4));
      expect(summary['error'], equals(1));
      expect(summary['warning'], equals(2));
      expect(summary['info'], equals(1));
    });

    test(
      'severity counts are 0 (not absent) when no findings of that type',
      () {
        final findings = [
          _finding(severity: Severity.error, fingerprint: 'fp1'),
        ];
        final output = const JsonReporter().render(
          _payload(findings: findings),
        );
        final doc = jsonDecode(output) as Map<String, dynamic>;
        final summary = doc['summary'] as Map<String, dynamic>;
        expect(summary['warning'], equals(0));
        expect(summary['info'], equals(0));
      },
    );
  });

  // -------------------------------------------------------------------------
  // AC4: Finding fields mirror the Finding model
  // -------------------------------------------------------------------------
  group('Finding fields', () {
    test('finding has all required fields', () {
      final f = _finding(line: 10, column: 5);
      final output = const JsonReporter().render(_payload(findings: [f]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final finding = (doc['findings'] as List).first as Map<String, dynamic>;
      expect(finding.containsKey('ruleId'), isTrue);
      expect(finding.containsKey('severity'), isTrue);
      expect(finding.containsKey('filePath'), isTrue);
      expect(finding.containsKey('line'), isTrue);
      expect(finding.containsKey('column'), isTrue);
      expect(finding.containsKey('message'), isTrue);
      expect(finding.containsKey('fingerprint'), isTrue);
    });

    test('severity is lowercase enum name', () {
      for (final sev in Severity.values) {
        final f = _finding(severity: sev, fingerprint: sev.name);
        final output = const JsonReporter().render(_payload(findings: [f]));
        final doc = jsonDecode(output) as Map<String, dynamic>;
        final finding = (doc['findings'] as List).first as Map<String, dynamic>;
        expect(
          finding['severity'],
          equals(sev.name),
        ); // 'error','warning','info'
      }
    });

    test('column is null in JSON when Finding.column is null', () {
      final f = _finding(column: null);
      final output = const JsonReporter().render(_payload(findings: [f]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final finding = (doc['findings'] as List).first as Map<String, dynamic>;
      expect(finding['column'], isNull);
    });

    test('column has correct value when Finding.column is set', () {
      final f = _finding(column: 7);
      final output = const JsonReporter().render(_payload(findings: [f]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final finding = (doc['findings'] as List).first as Map<String, dynamic>;
      expect(finding['column'], equals(7));
    });

    test('fingerprint is preserved', () {
      final f = _finding(fingerprint: 'deadbeef');
      final output = const JsonReporter().render(_payload(findings: [f]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final finding = (doc['findings'] as List).first as Map<String, dynamic>;
      expect(finding['fingerprint'], equals('deadbeef'));
    });
  });

  // -------------------------------------------------------------------------
  // AC5: filePath is relative and forward-slash-normalised
  // -------------------------------------------------------------------------
  group('Path normalisation', () {
    test('filePath is relative to projectRoot', () {
      final f = _finding(filePath: '/project/lib/src/foo.dart');
      final output = const JsonReporter().render(
        _payload(findings: [f], projectRoot: '/project'),
      );
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final finding = (doc['findings'] as List).first as Map<String, dynamic>;
      expect(finding['filePath'], equals('lib/src/foo.dart'));
    });

    test('filePath uses forward slashes', () {
      final f = _finding(filePath: '/project/lib/src/foo.dart');
      final output = const JsonReporter().render(
        _payload(findings: [f], projectRoot: '/project'),
      );
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final finding = (doc['findings'] as List).first as Map<String, dynamic>;
      expect((finding['filePath'] as String), isNot(contains('\\')));
    });

    test('filePath has no leading slash', () {
      final f = _finding(filePath: '/project/lib/src/foo.dart');
      final output = const JsonReporter().render(
        _payload(findings: [f], projectRoot: '/project'),
      );
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final finding = (doc['findings'] as List).first as Map<String, dynamic>;
      expect((finding['filePath'] as String), isNot(startsWith('/')));
    });

    test('output contains no absolute project root path', () {
      final f = _finding(filePath: '/secret/project/lib/src/foo.dart');
      final output = const JsonReporter().render(
        _payload(findings: [f], projectRoot: '/secret/project'),
      );
      expect(output, isNot(contains('/secret/project')));
    });
  });

  // -------------------------------------------------------------------------
  // AC6: Empty run produces well-formed document
  // -------------------------------------------------------------------------
  group('Empty findings', () {
    test('empty run: summary.total == 0', () {
      final output = const JsonReporter().render(_payload(findings: []));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final summary = doc['summary'] as Map<String, dynamic>;
      expect(summary['total'], equals(0));
    });

    test('empty run: findings is an empty array', () {
      final output = const JsonReporter().render(_payload(findings: []));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      expect(doc['findings'], isEmpty);
    });

    test('empty run: all severity counts are 0', () {
      final output = const JsonReporter().render(_payload(findings: []));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final summary = doc['summary'] as Map<String, dynamic>;
      expect(summary['error'], equals(0));
      expect(summary['warning'], equals(0));
      expect(summary['info'], equals(0));
    });

    test('empty run: output is still valid JSON', () {
      final output = const JsonReporter().render(_payload(findings: []));
      expect(() => jsonDecode(output), returnsNormally);
    });
  });

  // -------------------------------------------------------------------------
  // AC7: Byte-identical reproducibility
  // -------------------------------------------------------------------------
  group('Reproducibility', () {
    test('render twice with same payload produces identical string', () {
      final reporter = const JsonReporter();
      final payload = _payload(findings: [_finding()]);
      expect(reporter.render(payload), equals(reporter.render(payload)));
    });

    test('output contains no timestamp patterns (ISO 8601)', () {
      final output = const JsonReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(output, isNot(matches(RegExp(r'\d{4}-\d{2}-\d{2}T'))));
    });
  });

  // -------------------------------------------------------------------------
  // AC8: reporterFor('json') dispatch
  // -------------------------------------------------------------------------
  group('reporterFor dispatch', () {
    test('reporterFor("json") returns JsonReporter', () {
      final reporter = reporterFor('json');
      expect(reporter, isA<JsonReporter>());
    });

    test('reporterFor("json") does not throw', () {
      expect(() => reporterFor('json'), returnsNormally);
    });
  });
}

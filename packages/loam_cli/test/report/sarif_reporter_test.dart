@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/report/reporter.dart';
import 'package:loam/src/report/reporter_dispatch.dart';
import 'package:loam/src/report/sarif_reporter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Shared fixture helpers
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
}) => ReportPayload(
  findings: findings,
  projectRoot: projectRoot,
  rulesetVersion: rulesetVersion,
  toolVersion: toolVersion,
  isTty: isTty,
);

late JsonSchema _sarifSchema;

void main() {
  setUpAll(() async {
    final schemaPath = p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'sarif',
      'sarif-schema-2.1.0.json',
    );
    final schemaJson =
        jsonDecode(File(schemaPath).readAsStringSync()) as Map<String, dynamic>;
    _sarifSchema = JsonSchema.create(schemaJson);
  });

  // -------------------------------------------------------------------------
  // AC1: SarifReporter produces SARIF 2.1.0 via dart:convert only
  // -------------------------------------------------------------------------
  group('SarifReporter SARIF 2.1.0 structure', () {
    test('output is valid JSON', () {
      final output = SarifReporter().render(_payload(findings: [_finding()]));
      expect(() => jsonDecode(output), returnsNormally);
    });

    test('\$schema is set to SARIF 2.1.0 schema URL', () {
      final output = SarifReporter().render(_payload(findings: [_finding()]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      expect(
        doc[r'$schema'],
        contains('sarif-schema-2.1.0'),
        reason: '\$schema must reference SARIF 2.1.0',
      );
    });

    test('version == "2.1.0"', () {
      final output = SarifReporter().render(_payload(findings: [_finding()]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      expect(doc['version'], equals('2.1.0'));
    });

    test('has exactly one run', () {
      final output = SarifReporter().render(_payload(findings: [_finding()]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final runs = doc['runs'] as List<dynamic>;
      expect(runs, hasLength(1));
    });

    test('tool.driver.name == "loam"', () {
      final output = SarifReporter().render(_payload(findings: [_finding()]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final driver =
          ((doc['runs'] as List).first
                  as Map<String, dynamic>)['tool']['driver']
              as Map<String, dynamic>;
      expect(driver['name'], equals('loam'));
    });

    test('tool.driver.version == toolVersion from payload', () {
      final output = SarifReporter().render(
        _payload(findings: [_finding()], toolVersion: '1.2.3'),
      );
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final driver =
          ((doc['runs'] as List).first
                  as Map<String, dynamic>)['tool']['driver']
              as Map<String, dynamic>;
      expect(driver['version'], equals('1.2.3'));
    });

    test('tool.driver.informationUri == "https://getloam.dev"', () {
      final output = SarifReporter().render(_payload(findings: [_finding()]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final driver =
          ((doc['runs'] as List).first
                  as Map<String, dynamic>)['tool']['driver']
              as Map<String, dynamic>;
      expect(driver['informationUri'], equals('https://getloam.dev'));
    });
  });

  // -------------------------------------------------------------------------
  // AC2: Severity→level mapping
  // -------------------------------------------------------------------------
  group('Severity to SARIF level mapping', () {
    test('Severity.error → level "error"', () {
      final f = _finding(severity: Severity.error);
      final output = SarifReporter().render(_payload(findings: [f]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final results =
          ((doc['runs'] as List).first as Map<String, dynamic>)['results']
              as List<dynamic>;
      expect(results.first['level'], equals('error'));
    });

    test('Severity.warning → level "warning"', () {
      final f = _finding(severity: Severity.warning);
      final output = SarifReporter().render(_payload(findings: [f]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final results =
          ((doc['runs'] as List).first as Map<String, dynamic>)['results']
              as List<dynamic>;
      expect(results.first['level'], equals('warning'));
    });

    test('Severity.info → level "note"', () {
      final f = _finding(severity: Severity.info);
      final output = SarifReporter().render(_payload(findings: [f]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final results =
          ((doc['runs'] as List).first as Map<String, dynamic>)['results']
              as List<dynamic>;
      expect(results.first['level'], equals('note'));
    });
  });

  // -------------------------------------------------------------------------
  // AC3: URI relativization
  // -------------------------------------------------------------------------
  group('URI relativization', () {
    test('artifact URI is relative to projectRoot', () {
      final f = _finding(filePath: '/project/lib/src/foo.dart');
      final output = SarifReporter().render(
        _payload(findings: [f], projectRoot: '/project'),
      );
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final results =
          ((doc['runs'] as List).first as Map<String, dynamic>)['results']
              as List<dynamic>;
      final uri =
          ((results.first['locations'] as List)
                  .first)['physicalLocation']['artifactLocation']['uri']
              as String;
      expect(uri, equals('lib/src/foo.dart'));
    });

    test('URI uses forward slashes', () {
      final f = _finding(filePath: '/project/lib/src/foo.dart');
      final output = SarifReporter().render(
        _payload(findings: [f], projectRoot: '/project'),
      );
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final results =
          ((doc['runs'] as List).first as Map<String, dynamic>)['results']
              as List<dynamic>;
      final uri =
          ((results.first['locations'] as List)
                  .first)['physicalLocation']['artifactLocation']['uri']
              as String;
      expect(uri, isNot(contains('\\')));
    });

    test('URI has no leading slash', () {
      final f = _finding(filePath: '/project/lib/src/foo.dart');
      final output = SarifReporter().render(
        _payload(findings: [f], projectRoot: '/project'),
      );
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final results =
          ((doc['runs'] as List).first as Map<String, dynamic>)['results']
              as List<dynamic>;
      final uri =
          ((results.first['locations'] as List)
                  .first)['physicalLocation']['artifactLocation']['uri']
              as String;
      expect(uri, isNot(startsWith('/')));
    });

    test('region.startLine is always present', () {
      final f = _finding(line: 42);
      final output = SarifReporter().render(_payload(findings: [f]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final results =
          ((doc['runs'] as List).first as Map<String, dynamic>)['results']
              as List<dynamic>;
      final region =
          ((results.first['locations'] as List)
                  .first)['physicalLocation']['region']
              as Map<String, dynamic>;
      expect(region['startLine'], equals(42));
    });

    test('region.startColumn present when column != null', () {
      final f = _finding(line: 10, column: 5);
      final output = SarifReporter().render(_payload(findings: [f]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final results =
          ((doc['runs'] as List).first as Map<String, dynamic>)['results']
              as List<dynamic>;
      final region =
          ((results.first['locations'] as List)
                  .first)['physicalLocation']['region']
              as Map<String, dynamic>;
      expect(region['startColumn'], equals(5));
    });

    test('region.startColumn absent when column == null', () {
      final f = _finding(line: 10, column: null);
      final output = SarifReporter().render(_payload(findings: [f]));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final results =
          ((doc['runs'] as List).first as Map<String, dynamic>)['results']
              as List<dynamic>;
      final region =
          ((results.first['locations'] as List)
                  .first)['physicalLocation']['region']
              as Map<String, dynamic>;
      expect(region.containsKey('startColumn'), isFalse);
    });
  });

  // -------------------------------------------------------------------------
  // AC4: Deduplicated rules catalog
  // -------------------------------------------------------------------------
  group('Deduplicated rules catalog', () {
    test('each ruleId appears exactly once in tool.driver.rules', () {
      final findings = [
        _finding(ruleId: 'rule-a', fingerprint: 'fp1'),
        _finding(ruleId: 'rule-b', fingerprint: 'fp2'),
        _finding(ruleId: 'rule-a', fingerprint: 'fp3'), // duplicate
      ];
      final output = SarifReporter().render(_payload(findings: findings));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final rules =
          ((doc['runs'] as List).first
                  as Map<String, dynamic>)['tool']['driver']['rules']
              as List<dynamic>;
      final ruleIds = rules.map((r) => (r as Map)['id']).toList();
      expect(ruleIds, containsAll(['rule-a', 'rule-b']));
      expect(
        ruleIds.toSet().length,
        equals(ruleIds.length),
        reason: 'no duplicates in rules catalog',
      );
    });

    test('every result references a ruleId that is in the rules catalog', () {
      final findings = [
        _finding(ruleId: 'rule-a', fingerprint: 'fp1'),
        _finding(ruleId: 'rule-b', fingerprint: 'fp2'),
      ];
      final output = SarifReporter().render(_payload(findings: findings));
      final doc = jsonDecode(output) as Map<String, dynamic>;
      final run = (doc['runs'] as List).first as Map<String, dynamic>;
      final rules = (run['tool']['driver']['rules'] as List)
          .map((r) => (r as Map)['id'] as String)
          .toSet();
      final results = run['results'] as List<dynamic>;
      for (final result in results) {
        expect(
          rules,
          contains((result as Map)['ruleId']),
          reason: 'result ruleId must be in rules catalog',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // AC5: Reproducibility — no timestamp, no absolute paths, byte-identical
  // -------------------------------------------------------------------------
  group('Reproducibility', () {
    test('render twice with same input produces identical string', () {
      final reporter = SarifReporter();
      final payload = _payload(findings: [_finding()]);
      expect(reporter.render(payload), equals(reporter.render(payload)));
    });

    test('output contains no absolute paths from projectRoot', () {
      final f = _finding(filePath: '/secret/project/lib/src/foo.dart');
      final output = SarifReporter().render(
        _payload(findings: [f], projectRoot: '/secret/project'),
      );
      expect(output, isNot(contains('/secret/project')));
    });

    test('output contains no timestamp patterns (ISO 8601)', () {
      final output = SarifReporter().render(_payload(findings: [_finding()]));
      // Check for common timestamp patterns like 2024-01-01T...
      expect(output, isNot(matches(RegExp(r'\d{4}-\d{2}-\d{2}T'))));
    });
  });

  // -------------------------------------------------------------------------
  // AC6: Real schema validation against official SARIF 2.1.0 JSON Schema
  // -------------------------------------------------------------------------
  group('Schema validation', () {
    test('output validates against official SARIF 2.1.0 JSON schema', () {
      final findings = [
        _finding(
          ruleId: 'unused-public-exports',
          severity: Severity.warning,
          filePath: '/project/lib/src/foo.dart',
          line: 10,
          fingerprint: 'fp1',
        ),
        _finding(
          ruleId: 'unused-public-exports',
          severity: Severity.error,
          filePath: '/project/lib/src/bar.dart',
          line: 20,
          column: 5,
          fingerprint: 'fp2',
        ),
      ];
      final output = SarifReporter().render(_payload(findings: findings));
      final doc = jsonDecode(output);
      final result = _sarifSchema.validate(doc);
      expect(
        result.isValid,
        isTrue,
        reason:
            'SARIF output must validate against the official schema. '
            'Errors: ${result.errors}',
      );
    });

    test(
      'each result has ruleId, level, and locations[].physicalLocation.region',
      () {
        final f = _finding(line: 5, column: 3);
        final output = SarifReporter().render(_payload(findings: [f]));
        final doc = jsonDecode(output) as Map<String, dynamic>;
        final results =
            ((doc['runs'] as List).first as Map<String, dynamic>)['results']
                as List<dynamic>;
        for (final result in results) {
          final r = result as Map<String, dynamic>;
          expect(r.containsKey('ruleId'), isTrue);
          expect(r.containsKey('level'), isTrue);
          final locations = r['locations'] as List<dynamic>;
          expect(locations, isNotEmpty);
          final physLoc =
              (locations.first as Map<String, dynamic>)['physicalLocation']
                  as Map<String, dynamic>;
          expect(physLoc.containsKey('region'), isTrue);
        }
      },
    );

    test('empty findings list produces schema-valid SARIF', () {
      final output = SarifReporter().render(_payload(findings: []));
      final doc = jsonDecode(output);
      final result = _sarifSchema.validate(doc);
      expect(
        result.isValid,
        isTrue,
        reason: 'Empty findings SARIF must also be schema-valid',
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC7: reporterFor dispatch
  // -------------------------------------------------------------------------
  group('reporterFor dispatch', () {
    test('reporterFor("sarif") returns SarifReporter', () {
      final reporter = reporterFor('sarif');
      expect(reporter, isA<SarifReporter>());
    });

    test('SarifReporter implements Reporter interface', () {
      final Reporter reporter = SarifReporter();
      expect(reporter.render(_payload()), isA<String>());
    });
  });
}

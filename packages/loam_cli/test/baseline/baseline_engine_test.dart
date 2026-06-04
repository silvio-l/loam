@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/baseline/baseline_engine.dart';
import 'package:loam/src/model/finding.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

List<Finding> _makeFindings() => [
  const Finding(
    ruleId: 'unused-public-exports',
    severity: Severity.warning,
    filePath: 'lib/src/foo.dart',
    line: 10,
    message: 'Unused export: Foo',
    fingerprint: 'abc123def456abcd',
  ),
  const Finding(
    ruleId: 'unused-public-exports',
    severity: Severity.warning,
    filePath: 'lib/src/bar.dart',
    line: 5,
    message: 'Unused export: Bar',
    fingerprint: '1234567890abcdef',
  ),
];

void main() {
  late Directory tempDir;
  late BaselineEngine engine;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('loam_baseline_test_');
    engine = BaselineEngine(projectRoot: tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  // ---------------------------------------------------------------------------
  // AC1: write() produces a baseline.json with the correct schema
  // ---------------------------------------------------------------------------

  group('BaselineEngine.write()', () {
    test(
      'creates baseline.json with schemaVersion, rulesetVersion and findings',
      () async {
        final findings = _makeFindings();
        engine.write(findings, 'ruleset@1');

        final file = File('${tempDir.path}/baseline.json');
        expect(
          file.existsSync(),
          isTrue,
          reason: 'baseline.json must exist after write',
        );

        final content = file.readAsStringSync();
        expect(content, contains('"schemaVersion"'));
        expect(content, contains('"rulesetVersion"'));
        expect(content, contains('"findings"'));
      },
    );

    test('baseline.json contains all fingerprints from the findings', () async {
      final findings = _makeFindings();
      engine.write(findings, 'ruleset@1');

      final file = File('${tempDir.path}/baseline.json');
      final content = file.readAsStringSync();
      for (final f in findings) {
        expect(
          content,
          contains(f.fingerprint),
          reason: 'baseline.json must contain fingerprint ${f.fingerprint}',
        );
      }
    });

    test(
      'baseline.json contains readable context fields per finding',
      () async {
        final findings = _makeFindings();
        engine.write(findings, 'ruleset@1');

        final file = File('${tempDir.path}/baseline.json');
        final content = file.readAsStringSync();

        // non-authoritative context: ruleId, filePath, line, message
        expect(content, contains('"ruleId"'));
        expect(content, contains('"filePath"'));
        expect(content, contains('"line"'));
        expect(content, contains('"message"'));
      },
    );

    test(
      'write() uses stable sort order (same as AnalysisRunner: filePath → line → fingerprint)',
      () async {
        // We have two findings: bar.dart:5 and foo.dart:10 — bar comes first alphabetically
        final findings =
            _makeFindings(); // foo.dart then bar.dart in source order
        engine.write(findings, 'ruleset@1');

        final baseline = engine.read();
        expect(baseline.findings.length, equals(2));
        // After stable sort, bar.dart should come before foo.dart
        expect(baseline.findings[0].filePath, equals('lib/src/bar.dart'));
        expect(baseline.findings[1].filePath, equals('lib/src/foo.dart'));
      },
    );
  });

  // ---------------------------------------------------------------------------
  // AC2: Roundtrip write → read preserves fingerprints
  // ---------------------------------------------------------------------------

  group('BaselineEngine roundtrip', () {
    test(
      'write then read preserves finding fingerprints identically',
      () async {
        final findings = _makeFindings();
        engine.write(findings, 'ruleset@2');

        final baseline = engine.read();
        expect(
          baseline.findings.map((f) => f.fingerprint).toList(),
          containsAllInOrder(
            findings.map((f) => f.fingerprint).toList()
              ..sort(), // sort by fingerprint order because write sorts
          ),
        );
      },
    );

    test('write then read preserves rulesetVersion', () async {
      engine.write(_makeFindings(), 'ruleset@42');
      final baseline = engine.read();
      expect(baseline.rulesetVersion, equals('ruleset@42'));
    });

    test('write then read preserves schemaVersion', () async {
      engine.write(_makeFindings(), 'ruleset@1');
      final baseline = engine.read();
      expect(baseline.schemaVersion, equals(1));
    });

    test('roundtrip preserves all readable context fields', () async {
      final findings = _makeFindings();
      engine.write(findings, 'ruleset@1');

      final baseline = engine.read();
      final fingerprints = baseline.findings.map((f) => f.fingerprint).toSet();
      for (final f in findings) {
        expect(fingerprints, contains(f.fingerprint));
      }

      // Check context fields are preserved
      final barEntry = baseline.findings.firstWhere(
        (e) => e.fingerprint == '1234567890abcdef',
      );
      expect(barEntry.ruleId, equals('unused-public-exports'));
      expect(barEntry.filePath, equals('lib/src/bar.dart'));
      expect(barEntry.line, equals(5));
      expect(barEntry.message, equals('Unused export: Bar'));
    });
  });

  // ---------------------------------------------------------------------------
  // AC3: read() throws clear errors on missing and corrupt baseline.json
  // ---------------------------------------------------------------------------

  group('BaselineEngine.read() error handling', () {
    test('read() throws BaselineException when baseline.json is missing', () {
      // tempDir has no baseline.json yet
      expect(
        () => engine.read(),
        throwsA(isA<BaselineException>()),
        reason: 'must throw BaselineException on missing file',
      );
    });

    test('BaselineException message mentions "missing" for missing file', () {
      try {
        engine.read();
        fail('should have thrown');
      } on BaselineException catch (e) {
        expect(e.message.toLowerCase(), contains('missing'));
      }
    });

    test(
      'read() throws BaselineException when baseline.json is corrupt (not valid JSON)',
      () {
        File(
          '${tempDir.path}/baseline.json',
        ).writeAsStringSync('NOT VALID JSON }{');
        expect(
          () => engine.read(),
          throwsA(isA<BaselineException>()),
          reason: 'must throw BaselineException on corrupt JSON',
        );
      },
    );

    test(
      'BaselineException message mentions "corrupt" or "parse" for corrupt file',
      () {
        File(
          '${tempDir.path}/baseline.json',
        ).writeAsStringSync('NOT VALID JSON }{');
        try {
          engine.read();
          fail('should have thrown');
        } on BaselineException catch (e) {
          final msg = e.message.toLowerCase();
          expect(
            msg.contains('corrupt') ||
                msg.contains('parse') ||
                msg.contains('invalid'),
            isTrue,
            reason: 'error message should mention corrupt/parse/invalid',
          );
        }
      },
    );

    test(
      'read() throws BaselineException when baseline.json has wrong schema (valid JSON but missing fields)',
      () {
        File('${tempDir.path}/baseline.json').writeAsStringSync('{"foo": 42}');
        expect(
          () => engine.read(),
          throwsA(isA<BaselineException>()),
          reason: 'must throw BaselineException on schema mismatch',
        );
      },
    );
  });
}

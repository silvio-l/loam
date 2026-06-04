@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/model/finding.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'unused_exports_fixture',
    ),
  );

  // ---------------------------------------------------------------------------
  // AC1: AnalysisRunner.run() returns sorted findings via the active rule(s)
  // ---------------------------------------------------------------------------

  test(
    'run() returns a non-empty list of findings for fixture project',
    () async {
      final runner = AnalysisRunner();
      final findings = await runner.run(fixturePath);
      expect(findings, isNotEmpty);
    },
  );

  test('run() returns only Finding instances', () async {
    final runner = AnalysisRunner();
    final findings = await runner.run(fixturePath);
    expect(findings, everyElement(isA<Finding>()));
  });

  // ---------------------------------------------------------------------------
  // AC1: Deterministic sort: filePath → line → fingerprint
  // ---------------------------------------------------------------------------

  test(
    'findings are sorted deterministically by filePath, line, fingerprint',
    () async {
      final runner = AnalysisRunner();
      final findings = await runner.run(fixturePath);

      for (var i = 0; i < findings.length - 1; i++) {
        final a = findings[i];
        final b = findings[i + 1];

        final pathCmp = a.filePath.compareTo(b.filePath);
        if (pathCmp < 0) continue; // path strictly increasing → ok
        if (pathCmp > 0) {
          fail(
            'findings not sorted by filePath: '
            '${a.filePath} should come before ${b.filePath}',
          );
        }
        // same path: check line
        if (a.line < b.line) continue;
        if (a.line > b.line) {
          fail(
            'findings not sorted by line at ${a.filePath}: '
            '${a.line} should come before ${b.line}',
          );
        }
        // same path + same line: check fingerprint
        expect(
          a.fingerprint.compareTo(b.fingerprint),
          lessThanOrEqualTo(0),
          reason: 'fingerprints not sorted at ${a.filePath}:${a.line}',
        );
      }
    },
  );

  // ---------------------------------------------------------------------------
  // AC1 (Invariant 5): Two runs produce identical findings in identical order
  // ---------------------------------------------------------------------------

  test(
    'two consecutive runs produce identical findings (Invariant 5)',
    () async {
      final runner = AnalysisRunner();
      final run1 = await runner.run(fixturePath);
      final run2 = await runner.run(fixturePath);

      expect(run1.length, equals(run2.length));
      for (var i = 0; i < run1.length; i++) {
        expect(
          run1[i].fingerprint,
          equals(run2[i].fingerprint),
          reason: 'fingerprint at index $i must match across runs',
        );
        expect(
          run1[i].message,
          equals(run2[i].message),
          reason: 'message at index $i must match across runs',
        );
        expect(
          run1[i].filePath,
          equals(run2[i].filePath),
          reason: 'filePath at index $i must match across runs',
        );
        expect(
          run1[i].line,
          equals(run2[i].line),
          reason: 'line at index $i must match across runs',
        );
      }
    },
  );

  // ---------------------------------------------------------------------------
  // AC1: All findings carry ruleId = unused-public-exports (MVP rule)
  // ---------------------------------------------------------------------------

  test(
    'all findings carry ruleId unused-public-exports (MVP registry)',
    () async {
      final runner = AnalysisRunner();
      final findings = await runner.run(fixturePath);
      for (final f in findings) {
        expect(f.ruleId, equals('unused-public-exports'));
      }
    },
  );
}

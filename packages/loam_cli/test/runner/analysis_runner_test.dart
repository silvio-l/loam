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
  // AC1: findings include unused-public-exports entries (fixture-based check)
  //
  // Note: AnalysisRunner now runs all registered rules. The unused_exports_fixture
  // is designed to trigger unused-public-exports findings. Complexity-hotspots
  // findings may also appear for any function in the fixture that exceeds the
  // default thresholds — but the fixture contains only trivial functions, so
  // only unused-public-exports findings are expected here.
  // ---------------------------------------------------------------------------

  test(
    'findings include unused-public-exports entries (fixture has unused symbols)',
    () async {
      final runner = AnalysisRunner();
      final findings = await runner.run(fixturePath);
      final unusedExportFindings = findings
          .where((f) => f.ruleId == 'unused-public-exports')
          .toList();
      expect(
        unusedExportFindings,
        isNotEmpty,
        reason:
            'unused_exports_fixture must produce at least one unused-public-exports finding',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // rulesetVersion: derived from active rule set, not hardcoded
  // ---------------------------------------------------------------------------

  test('rulesetVersion starts with "ruleset@"', () {
    expect(AnalysisRunner.rulesetVersion, startsWith('ruleset@'));
  });

  test('rulesetVersion is deterministic across calls', () {
    final v1 = AnalysisRunner.rulesetVersion;
    final v2 = AnalysisRunner.rulesetVersion;
    expect(v1, equals(v2));
  });

  test('activeRuleIds contains unused-public-exports', () {
    expect(AnalysisRunner.activeRuleIds, contains('unused-public-exports'));
  });

  // ---------------------------------------------------------------------------
  // analyze(): findings + suppressed count + scope stats
  // ---------------------------------------------------------------------------

  group('analyze() outcome', () {
    test('findings match run() exactly', () async {
      final runner = AnalysisRunner();
      final viaRun = await runner.run(fixturePath);
      final outcome = await runner.analyze(fixturePath);
      expect(
        outcome.findings.map((f) => f.fingerprint),
        viaRun.map((f) => f.fingerprint),
      );
    });

    test('stats report files, lib subset and all active rules', () async {
      final outcome = await AnalysisRunner().analyze(fixturePath);
      expect(outcome.stats.filesAnalyzed, greaterThan(0));
      expect(
        outcome.stats.libFilesAnalyzed,
        lessThanOrEqualTo(outcome.stats.filesAnalyzed),
      );
      expect(outcome.stats.linesAnalyzed, greaterThan(0));
      expect(outcome.stats.rulesRun, AnalysisRunner.activeRuleIds);
    });

    test(
      'suppressedCount counts inline-ignored findings (raw − surviving)',
      () async {
        final suppressionFixture = p.normalize(
          p.join(
            Directory.current.path,
            'test',
            'fixtures',
            'inline_suppression_fixture',
          ),
        );
        final outcome = await AnalysisRunner().analyze(suppressionFixture);
        expect(
          outcome.suppressedCount,
          greaterThan(0),
          reason: 'the fixture carries real // loam-ignore: directives',
        );
      },
    );
  });
}

@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/rules/slop_empty_catch_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'slop_empty_catch_fixture',
    ),
  );

  late ProjectLoadResult loadResult;

  setUpAll(() async {
    // dart pub get is idempotent; re-runs after a fresh clone regenerate
    // .dart_tool/package_config.json which is gitignored.
    final pubGetResult = await Process.run('dart', [
      'pub',
      'get',
    ], workingDirectory: fixturePath);
    if (pubGetResult.exitCode != 0) {
      fail(
        'dart pub get failed in fixture:\n'
        '${pubGetResult.stdout}\n${pubGetResult.stderr}',
      );
    }

    final loader = const ProjectLoader();
    loadResult = await loader.load(fixturePath);

    // The fixture must load cleanly.
    expect(
      loadResult.errors,
      isEmpty,
      reason:
          'Fixture must load cleanly. '
          'Errors: ${loadResult.errors.map((e) => "${e.path}: ${e.reason}").join("; ")}',
    );
  });

  SlopEmptyCatchRule makeRule() => SlopEmptyCatchRule(projectRoot: fixturePath);

  // ---------------------------------------------------------------------------
  // Interface contract
  // ---------------------------------------------------------------------------

  test('ruleId is slop-empty-catch', () {
    expect(makeRule().ruleId, 'slop-empty-catch');
  });

  test('static ruleIdStatic matches ruleId', () {
    expect(SlopEmptyCatchRule.ruleIdStatic, makeRule().ruleId);
  });

  test('category is RuleCategory.slop', () {
    expect(makeRule().category, RuleCategory.slop);
  });

  // ---------------------------------------------------------------------------
  // AC1: Positive — empty catch body → Finding
  // ---------------------------------------------------------------------------

  test('AC1: empty catch body {} → 1 Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('empty_catch.dart'))
        .toList();
    expect(
      hits,
      hasLength(1),
      reason:
          'Expected exactly 1 finding in empty_catch.dart. '
          'Got: ${hits.map((f) => "${f.line}: ${f.message}").join(", ")}',
    );
  });

  test('AC1: empty-catch finding ruleId is slop-empty-catch', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.ruleId, 'slop-empty-catch');
    }
  });

  test('AC1: empty-catch finding severity is Severity.warning', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.severity, Severity.warning);
    }
  });

  test('AC1: empty-catch finding kind is "empty-catch"', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.kind, 'empty-catch');
    }
  });

  // ---------------------------------------------------------------------------
  // AC1: Positive — comment-only catch body → Finding
  // ---------------------------------------------------------------------------

  test('AC1: comment-only catch body → 1 Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('comment_only_catch.dart'))
        .toList();
    expect(
      hits,
      hasLength(1),
      reason:
          'Expected exactly 1 finding in comment_only_catch.dart. '
          'Got: ${hits.map((f) => "${f.line}: ${f.message}").join(", ")}',
    );
  });

  // ---------------------------------------------------------------------------
  // AC1: Total finding count across all fixture files
  // ---------------------------------------------------------------------------

  test('AC1: total findings — exactly 2 (one per positive fixture file)', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings,
      hasLength(2),
      reason:
          'Expected exactly 2 findings total (empty_catch + comment_only_catch). '
          'Got: ${findings.map((f) => "${f.filePath}:${f.line} ${f.message}").join("; ")}',
    );
  });

  // ---------------------------------------------------------------------------
  // AC2: Negative — rethrow/throw in catch → no Finding
  // ---------------------------------------------------------------------------

  test('AC2: rethrow in catch → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('rethrow_catch.dart'))
        .toList();
    expect(
      hits,
      isEmpty,
      reason: 'rethrow_catch.dart should produce 0 findings',
    );
  });

  // ---------------------------------------------------------------------------
  // AC2: Negative — logging call in catch → no Finding
  // ---------------------------------------------------------------------------

  test('AC2: logging call in catch → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('logging_catch.dart'))
        .toList();
    expect(
      hits,
      isEmpty,
      reason: 'logging_catch.dart should produce 0 findings',
    );
  });

  // ---------------------------------------------------------------------------
  // AC4 / AC7: Generated file (*.g.dart) → no Finding
  // ---------------------------------------------------------------------------

  test('AC4: generated file (*.g.dart) → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings.where((f) => f.filePath.endsWith('.g.dart')).toList();
    expect(hits, isEmpty, reason: 'Generated files must be skipped entirely');
  });

  // ---------------------------------------------------------------------------
  // AC4: Fingerprint stability — two independent runs produce identical fingerprints
  // ---------------------------------------------------------------------------

  test('AC4: fingerprints are identical across two independent runs', () {
    final run1 = makeRule().run(loadResult);
    final run2 = makeRule().run(loadResult);

    expect(run1.length, run2.length);
    for (var i = 0; i < run1.length; i++) {
      expect(
        run1[i].fingerprint,
        run2[i].fingerprint,
        reason: 'Fingerprint mismatch at index $i',
      );
    }
  });

  test('AC4: each fingerprint is exactly 16 characters', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.fingerprint.length, 16, reason: 'Fingerprint: ${f.fingerprint}');
    }
  });

  test('AC4: all fingerprints are distinct', () {
    final findings = makeRule().run(loadResult);
    final fingerprints = findings.map((f) => f.fingerprint).toSet();
    expect(
      fingerprints.length,
      findings.length,
      reason: 'All findings must have distinct fingerprints',
    );
  });

  // ---------------------------------------------------------------------------
  // AC5: remedy is non-empty
  // ---------------------------------------------------------------------------

  test('AC5: remedy is non-empty', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.remedy, isNotNull);
      expect(f.remedy, isNotEmpty);
    }
  });

  // ---------------------------------------------------------------------------
  // AC3: Registry — rule is in fullRegistryIds and activeIdsForCategory(slop)
  // ---------------------------------------------------------------------------

  test('AC3: slop-empty-catch is in fullRegistryIds', () {
    expect(AnalysisRunner.fullRegistryIds, contains('slop-empty-catch'));
  });

  test('AC3: slop-empty-catch belongs to RuleCategory.slop', () {
    final slopIds = AnalysisRunner.activeIdsForCategory(RuleCategory.slop);
    expect(slopIds, contains('slop-empty-catch'));
  });

  test('AC3: AnalysisRunner with default config includes slop-empty-catch', () {
    const config = LoamConfig.defaults();
    final ids = AnalysisRunner.activeRuleIdsForConfig(config);
    expect(ids, contains('slop-empty-catch'));
  });

  test(
    'AC3: Rule disabled via toggle is excluded from activeRuleIdsForConfig',
    () {
      final config = LoamConfig(
        ruleToggles: const {'slop-empty-catch': false},
        ignoreGlobs: const [],
      );
      final ids = AnalysisRunner.activeRuleIdsForConfig(config);
      expect(ids, isNot(contains('slop-empty-catch')));
    },
  );

  // ---------------------------------------------------------------------------
  // AC4: loam scan delivers same slop findings as loam slop (category-filter test)
  // ---------------------------------------------------------------------------

  test(
    'AC4: categoryFilter(slop) findings ⊆ unrestricted findings for this fixture',
    () async {
      // AnalysisRunner with slop filter only
      final slopFindings = await AnalysisRunner(
        categoryFilter: RuleCategory.slop,
      ).run(fixturePath);

      // AnalysisRunner without filter (all rules)
      final allFindings = await AnalysisRunner().run(fixturePath);

      // Every slop finding must also appear in the full scan
      for (final sf in slopFindings) {
        expect(
          allFindings.any(
            (af) => af.fingerprint == sf.fingerprint && af.ruleId == sf.ruleId,
          ),
          isTrue,
          reason:
              'Slop finding ${sf.fingerprint} (${sf.ruleId}) not in full scan',
        );
      }
    },
  );
}

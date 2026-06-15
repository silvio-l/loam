@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/rules/slop_unjustified_ignore_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'slop_unjustified_ignore_fixture',
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

    // The fixture must load cleanly (no generated-file errors expected).
    expect(
      loadResult.errors,
      isEmpty,
      reason:
          'Fixture must load cleanly. '
          'Errors: ${loadResult.errors.map((e) => "${e.path}: ${e.reason}").join("; ")}',
    );
  });

  SlopUnjustifiedIgnoreRule makeRule() =>
      SlopUnjustifiedIgnoreRule(projectRoot: fixturePath);

  // ---------------------------------------------------------------------------
  // Interface contract
  // ---------------------------------------------------------------------------

  test('ruleId is slop-unjustified-ignore', () {
    expect(makeRule().ruleId, 'slop-unjustified-ignore');
  });

  test('static ruleIdStatic matches ruleId', () {
    expect(SlopUnjustifiedIgnoreRule.ruleIdStatic, makeRule().ruleId);
  });

  test('category is RuleCategory.slop', () {
    expect(makeRule().category, RuleCategory.slop);
  });

  // ---------------------------------------------------------------------------
  // AC2: Positive — // ignore: without justification → Finding
  // ---------------------------------------------------------------------------

  test('AC2: // ignore: without inline or above reason → 1 Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('unjustified_ignore.dart'))
        .toList();
    expect(
      hits,
      hasLength(1),
      reason:
          'Expected exactly 1 finding in unjustified_ignore.dart. '
          'Got: ${hits.map((f) => "${f.line}: ${f.message}").join(", ")}',
    );
  });

  test('AC2: finding ruleId is slop-unjustified-ignore', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.ruleId, 'slop-unjustified-ignore');
    }
  });

  test('AC2: finding severity is Severity.info', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.severity, Severity.info);
    }
  });

  test('AC2: finding kind is "unjustified-ignore"', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.kind, 'unjustified-ignore');
    }
  });

  test('AC2: unjustified // ignore: is on the reported line', () {
    final findings = makeRule().run(loadResult);
    final hit = findings
        .where((f) => f.filePath.contains('unjustified_ignore.dart'))
        .first;
    // The // ignore: is on line 5 of unjustified_ignore.dart
    expect(hit.line, 5);
  });

  // ---------------------------------------------------------------------------
  // AC2: Positive — // ignore_for_file: without justification → Finding
  // ---------------------------------------------------------------------------

  test('AC2: // ignore_for_file: without reason → 1 Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('unjustified_ignore_for_file.dart'))
        .toList();
    expect(
      hits,
      hasLength(1),
      reason:
          'Expected exactly 1 finding in unjustified_ignore_for_file.dart. '
          'Got: ${hits.map((f) => "${f.line}: ${f.message}").join(", ")}',
    );
  });

  test('AC2: // ignore_for_file: finding is on line 1', () {
    final findings = makeRule().run(loadResult);
    final hit = findings
        .where((f) => f.filePath.contains('unjustified_ignore_for_file.dart'))
        .first;
    // The // ignore_for_file: is on line 1 of unjustified_ignore_for_file.dart
    expect(hit.line, 1);
  });

  // ---------------------------------------------------------------------------
  // AC2: Total finding count across all fixture files
  // ---------------------------------------------------------------------------

  test('AC2: total findings — exactly 2 (one per unjustified fixture file)', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings,
      hasLength(2),
      reason:
          'Expected exactly 2 findings total (one per unjustified fixture). '
          'Got: ${findings.map((f) => "${f.filePath}:${f.line} ${f.message}").join("; ")}',
    );
  });

  // ---------------------------------------------------------------------------
  // AC2: Negative — inline justification → no Finding
  // ---------------------------------------------------------------------------

  test('AC2: // ignore: with inline reason → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('justified_inline.dart'))
        .toList();
    expect(
      hits,
      isEmpty,
      reason: 'justified_inline.dart should produce 0 findings',
    );
  });

  // ---------------------------------------------------------------------------
  // AC2: Negative — justification on line above → no Finding
  // ---------------------------------------------------------------------------

  test('AC2: // ignore: with comment on line above → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('justified_line_above.dart'))
        .toList();
    expect(
      hits,
      isEmpty,
      reason: 'justified_line_above.dart should produce 0 findings',
    );
  });

  // ---------------------------------------------------------------------------
  // AC7: Generated file (*.g.dart) → no Finding
  // ---------------------------------------------------------------------------

  test('AC7: generated file (*.g.dart) → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings.where((f) => f.filePath.endsWith('.g.dart')).toList();
    expect(hits, isEmpty, reason: 'Generated files must be skipped entirely');
  });

  // ---------------------------------------------------------------------------
  // AC8: Fingerprint stability — two independent runs produce identical fingerprints
  // ---------------------------------------------------------------------------

  test('AC8: fingerprints are identical across two independent runs', () {
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

  test('AC8: each fingerprint is exactly 16 characters', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.fingerprint.length, 16, reason: 'Fingerprint: ${f.fingerprint}');
    }
  });

  test('AC8: all fingerprints are distinct', () {
    final findings = makeRule().run(loadResult);
    final fingerprints = findings.map((f) => f.fingerprint).toSet();
    expect(
      fingerprints.length,
      findings.length,
      reason: 'All findings must have distinct fingerprints',
    );
  });

  // ---------------------------------------------------------------------------
  // AC8: remedy is non-empty
  // ---------------------------------------------------------------------------

  test('AC8: remedy is non-empty', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.remedy, isNotNull);
      expect(f.remedy, isNotEmpty);
    }
  });

  // ---------------------------------------------------------------------------
  // AC3: Registry — rule is in fullRegistryIds and activeIdsForCategory(slop)
  // ---------------------------------------------------------------------------

  test('AC3: slop-unjustified-ignore is in fullRegistryIds', () {
    expect(AnalysisRunner.fullRegistryIds, contains('slop-unjustified-ignore'));
  });

  test('AC3: slop-unjustified-ignore belongs to RuleCategory.slop', () {
    final slopIds = AnalysisRunner.activeIdsForCategory(RuleCategory.slop);
    expect(slopIds, contains('slop-unjustified-ignore'));
  });

  test(
    'AC3: AnalysisRunner with default config includes slop-unjustified-ignore',
    () {
      const config = LoamConfig.defaults();
      final ids = AnalysisRunner.activeRuleIdsForConfig(config);
      expect(ids, contains('slop-unjustified-ignore'));
    },
  );

  test(
    'AC3: Rule disabled via toggle is excluded from activeRuleIdsForConfig',
    () {
      final config = LoamConfig(
        ruleToggles: const {'slop-unjustified-ignore': false},
        ignoreGlobs: const [],
      );
      final ids = AnalysisRunner.activeRuleIdsForConfig(config);
      expect(ids, isNot(contains('slop-unjustified-ignore')));
    },
  );

  // ---------------------------------------------------------------------------
  // AC5: loam scan delivers same slop findings as loam slop (category-filter test)
  // ---------------------------------------------------------------------------

  test(
    'AC5: categoryFilter(slop) findings ⊆ unrestricted findings for this fixture',
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

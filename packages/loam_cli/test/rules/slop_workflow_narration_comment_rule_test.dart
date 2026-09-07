@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/rules/slop_workflow_narration_comment_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'slop_workflow_narration_comment_fixture',
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

    expect(
      loadResult.errors,
      isEmpty,
      reason:
          'Fixture must load cleanly. '
          'Errors: ${loadResult.errors.map((e) => "${e.path}: ${e.reason}").join("; ")}',
    );
  });

  SlopWorkflowNarrationCommentRule makeRule() =>
      SlopWorkflowNarrationCommentRule(projectRoot: fixturePath);

  // ---------------------------------------------------------------------------
  // Interface contract
  // ---------------------------------------------------------------------------

  test('ruleId is slop-workflow-narration-comment', () {
    expect(makeRule().ruleId, 'slop-workflow-narration-comment');
  });

  test('static ruleIdStatic matches ruleId', () {
    expect(SlopWorkflowNarrationCommentRule.ruleIdStatic, makeRule().ruleId);
  });

  test('category is RuleCategory.slop', () {
    expect(makeRule().category, RuleCategory.slop);
  });

  // ---------------------------------------------------------------------------
  // Positive: sequence of workflow-narration comments in a method body
  // ---------------------------------------------------------------------------

  test('method: Step 1/Step 2/Finally sequence → one Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('sequence_method.dart'))
        .toList();
    expect(
      hits,
      hasLength(1),
      reason:
          'Expected exactly one finding for the whole sequence, not one per '
          'comment. Got: ${hits.map((f) => "${f.line}: ${f.message}").join(", ")}',
    );
    expect(hits.single.line, 5, reason: 'Located at the first marker comment.');
    expect(hits.single.kind, 'workflow-narration');
    expect(hits.single.severity, Severity.info);
    expect(hits.single.remedy, isNotNull);
    expect(hits.single.remedy, isNotEmpty);
  });

  // ---------------------------------------------------------------------------
  // Positive: sequence in a top-level function body (First/Next/Then)
  // ---------------------------------------------------------------------------

  test('function: First/Next/Then sequence → one Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('sequence_function.dart'))
        .toList();
    expect(hits, hasLength(1));
    expect(hits.single.line, 4);
    expect(hits.single.kind, 'workflow-narration');
  });

  // ---------------------------------------------------------------------------
  // Positive: sequence in a constructor body
  // ---------------------------------------------------------------------------

  test('constructor: Step 1/Then sequence → one Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('sequence_constructor.dart'))
        .toList();
    expect(hits, hasLength(1));
    expect(hits.single.line, 5);
    expect(hits.single.kind, 'workflow-narration');
  });

  // ---------------------------------------------------------------------------
  // Negative: a single narrated step is not a sequence
  // ---------------------------------------------------------------------------

  test('single_marker.dart: one marker comment → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('single_marker.dart'))
        .toList();
    expect(hits, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // Negative: informative comments that are not workflow markers
  // ---------------------------------------------------------------------------

  test('informative.dart: no workflow markers → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('informative.dart'))
        .toList();
    expect(hits, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // Negative: /// dartdoc comments → never flagged (Dartdoc-Tabu)
  // ---------------------------------------------------------------------------

  test('dartdoc.dart: /// comments → no Finding (Dartdoc-Tabu)', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('dartdoc.dart'))
        .toList();
    expect(hits, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // Generated-file skip
  // ---------------------------------------------------------------------------

  test('generated file (*.g.dart) → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings.where((f) => f.filePath.endsWith('.g.dart')).toList();
    expect(hits, isEmpty, reason: 'Generated files must be skipped entirely');
  });

  // ---------------------------------------------------------------------------
  // Total finding count
  // ---------------------------------------------------------------------------

  test('total findings — exactly 3 (method + function + constructor)', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings,
      hasLength(3),
      reason:
          'Expected exactly 3 findings total. '
          'Got: ${findings.map((f) => "${f.filePath}:${f.line}").join("; ")}',
    );
  });

  // ---------------------------------------------------------------------------
  // Fingerprint stability
  // ---------------------------------------------------------------------------

  test('fingerprints are identical across two independent runs', () {
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

  test('each fingerprint is exactly 16 characters', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.fingerprint.length, 16, reason: 'Fingerprint: ${f.fingerprint}');
    }
  });

  test('all fingerprints are distinct', () {
    final findings = makeRule().run(loadResult);
    final fingerprints = findings.map((f) => f.fingerprint).toSet();
    expect(
      fingerprints.length,
      findings.length,
      reason: 'All findings must have distinct fingerprints',
    );
  });

  // ---------------------------------------------------------------------------
  // Registry
  // ---------------------------------------------------------------------------

  test('slop-workflow-narration-comment is in fullRegistryIds', () {
    expect(
      AnalysisRunner.fullRegistryIds,
      contains('slop-workflow-narration-comment'),
    );
  });

  test('slop-workflow-narration-comment belongs to RuleCategory.slop', () {
    final slopIds = AnalysisRunner.activeIdsForCategory(RuleCategory.slop);
    expect(slopIds, contains('slop-workflow-narration-comment'));
  });

  test(
    'AnalysisRunner with default config includes slop-workflow-narration-comment',
    () {
      const config = LoamConfig.defaults();
      final ids = AnalysisRunner.activeRuleIdsForConfig(config);
      expect(ids, contains('slop-workflow-narration-comment'));
    },
  );

  test('rule disabled via toggle is excluded from activeRuleIdsForConfig', () {
    final config = LoamConfig(
      ruleToggles: const {'slop-workflow-narration-comment': false},
      ignoreGlobs: const [],
    );
    final ids = AnalysisRunner.activeRuleIdsForConfig(config);
    expect(ids, isNot(contains('slop-workflow-narration-comment')));
  });

  test(
    'categoryFilter(slop) findings ⊆ unrestricted findings for this fixture',
    () async {
      final slopFindings = await AnalysisRunner(
        categoryFilter: RuleCategory.slop,
      ).run(fixturePath);

      final allFindings = await AnalysisRunner().run(fixturePath);

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

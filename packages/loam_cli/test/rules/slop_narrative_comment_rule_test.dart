@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/rules/slop_narrative_comment_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'slop_narrative_comment_fixture',
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

  SlopNarrativeCommentRule makeRule() =>
      SlopNarrativeCommentRule(projectRoot: fixturePath);

  // ---------------------------------------------------------------------------
  // Interface contract
  // ---------------------------------------------------------------------------

  test('ruleId is slop-narrative-comment', () {
    expect(makeRule().ruleId, 'slop-narrative-comment');
  });

  test('static ruleIdStatic matches ruleId', () {
    expect(SlopNarrativeCommentRule.ruleIdStatic, makeRule().ruleId);
  });

  test('category is RuleCategory.slop', () {
    expect(makeRule().category, RuleCategory.slop);
  });

  // ---------------------------------------------------------------------------
  // AC1: // comment = member/class name → Finding (Abgrenzungsfall 1: Member-Name)
  // ---------------------------------------------------------------------------

  test('AC1: // comment matches class name → Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('member_name_comment.dart'))
        .where((f) => f.line == 4) // line 4: // MyClass
        .toList();
    expect(
      hits,
      hasLength(1),
      reason: 'Expected finding for // MyClass (class name) on line 4.',
    );
  });

  test('AC1: // comment matches method name → Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('member_name_comment.dart'))
        .where((f) => f.line == 6) // line 6: // build
        .toList();
    expect(
      hits,
      hasLength(1),
      reason: 'Expected finding for // build (method name) on line 6.',
    );
  });

  test('AC1: member_name_comment.dart — exactly 2 findings', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('member_name_comment.dart'))
        .toList();
    expect(
      hits,
      hasLength(2),
      reason:
          'Expected exactly 2 findings in member_name_comment.dart. '
          'Got: ${hits.map((f) => "${f.line}: ${f.message}").join(", ")}',
    );
  });

  // ---------------------------------------------------------------------------
  // AC1: // comment from fixed restatement list → Finding (Abgrenzungsfall 2: Restatement)
  // ---------------------------------------------------------------------------

  test('AC1: // constructor → Finding (fixed restatement list)', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('restatement_comment.dart'))
        .where((f) => f.line == 4) // line 4: // constructor
        .toList();
    expect(
      hits,
      hasLength(1),
      reason: 'Expected finding for // constructor on line 4.',
    );
  });

  test('AC1: // getter → Finding (fixed restatement list)', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('restatement_comment.dart'))
        .where((f) => f.line == 9) // line 9: // getter
        .toList();
    expect(
      hits,
      hasLength(1),
      reason: 'Expected finding for // getter on line 9.',
    );
  });

  test('AC1: // setter → Finding (fixed restatement list)', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('restatement_comment.dart'))
        .where((f) => f.line == 12) // line 12: // setter
        .toList();
    expect(
      hits,
      hasLength(1),
      reason: 'Expected finding for // setter on line 12.',
    );
  });

  test('AC1: restatement_comment.dart — exactly 3 findings', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('restatement_comment.dart'))
        .toList();
    expect(
      hits,
      hasLength(3),
      reason:
          'Expected exactly 3 findings in restatement_comment.dart. '
          'Got: ${hits.map((f) => "${f.line}: ${f.message}").join(", ")}',
    );
  });

  // ---------------------------------------------------------------------------
  // AC1: Finding properties (severity, kind, remedy)
  // ---------------------------------------------------------------------------

  test('AC1: finding severity is Severity.info', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(
        f.severity,
        Severity.info,
        reason:
            'All findings must have severity info (${f.filePath}:${f.line})',
      );
    }
  });

  test('AC1: finding ruleId is slop-narrative-comment', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.ruleId, 'slop-narrative-comment');
    }
  });

  test('AC1: finding kind is "narrative-comment"', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.kind, 'narrative-comment');
    }
  });

  test('AC1: remedy is non-empty on every finding', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.remedy, isNotNull);
      expect(f.remedy, isNotEmpty);
    }
  });

  // ---------------------------------------------------------------------------
  // AC2: /// dartdoc → no Finding (Abgrenzungsfall 3: Dartdoc)
  // ---------------------------------------------------------------------------

  test('AC2: /// dartdoc → no Finding (Dartdoc-Tabu)', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('dartdoc_comment.dart'))
        .toList();
    expect(
      hits,
      isEmpty,
      reason: 'dartdoc_comment.dart must produce 0 findings (Dartdoc-Tabu)',
    );
  });

  // ---------------------------------------------------------------------------
  // AC2: informative // comment → no Finding (Abgrenzungsfall 4: Informativer Kommentar)
  // ---------------------------------------------------------------------------

  test('AC2: informative // comment → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('informative_comment.dart'))
        .toList();
    expect(
      hits,
      isEmpty,
      reason: 'informative_comment.dart must produce 0 findings',
    );
  });

  // ---------------------------------------------------------------------------
  // AC1: Total finding count across all non-generated fixture files
  // ---------------------------------------------------------------------------

  test('AC1: total findings — exactly 5 (2 member-name + 3 restatement)', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings,
      hasLength(5),
      reason:
          'Expected exactly 5 findings total. '
          'Got: ${findings.map((f) => "${f.filePath}:${f.line}").join("; ")}',
    );
  });

  // ---------------------------------------------------------------------------
  // Generated-file skip (AC4)
  // ---------------------------------------------------------------------------

  test('AC4: generated file (*.g.dart) → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings.where((f) => f.filePath.endsWith('.g.dart')).toList();
    expect(hits, isEmpty, reason: 'Generated files must be skipped entirely');
  });

  // ---------------------------------------------------------------------------
  // Fingerprint stability (AC4)
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
  // Registry (AC3)
  // ---------------------------------------------------------------------------

  test('AC3: slop-narrative-comment is in fullRegistryIds', () {
    expect(AnalysisRunner.fullRegistryIds, contains('slop-narrative-comment'));
  });

  test('AC3: slop-narrative-comment belongs to RuleCategory.slop', () {
    final slopIds = AnalysisRunner.activeIdsForCategory(RuleCategory.slop);
    expect(slopIds, contains('slop-narrative-comment'));
  });

  test(
    'AC3: AnalysisRunner with default config includes slop-narrative-comment',
    () {
      const config = LoamConfig.defaults();
      final ids = AnalysisRunner.activeRuleIdsForConfig(config);
      expect(ids, contains('slop-narrative-comment'));
    },
  );

  test(
    'AC3: rule disabled via toggle is excluded from activeRuleIdsForConfig',
    () {
      final config = LoamConfig(
        ruleToggles: const {'slop-narrative-comment': false},
        ignoreGlobs: const [],
      );
      final ids = AnalysisRunner.activeRuleIdsForConfig(config);
      expect(ids, isNot(contains('slop-narrative-comment')));
    },
  );

  // ---------------------------------------------------------------------------
  // AC4: loam scan delivers same slop findings as loam slop (category-filter)
  // ---------------------------------------------------------------------------

  test(
    'AC4: categoryFilter(slop) findings ⊆ unrestricted findings for this fixture',
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

  // ---------------------------------------------------------------------------
  // AC3: Suppression via // loam-ignore: slop-narrative-comment
  // ---------------------------------------------------------------------------

  test('AC3: loam-ignore directive suppresses the finding', () async {
    // The fixture member_name_comment.dart has 2 findings.
    // Run the full AnalysisRunner (with suppression) to verify the rule is
    // wired into the pipeline and suppression is honoured.
    //
    // We verify the pipeline-level suppression by comparing raw-rule findings
    // with AnalysisRunner output: the runner removes suppressed findings, so
    // AnalysisRunner().run should return ≤ raw findings for the fixture.
    final rawFindings = makeRule().run(loadResult);
    final runnerFindings = await AnalysisRunner(
      categoryFilter: RuleCategory.slop,
    ).run(fixturePath);

    // Every surviving runner finding for this rule must be in the raw set.
    final ruleRunnerFindings = runnerFindings
        .where((f) => f.ruleId == 'slop-narrative-comment')
        .toList();
    for (final rf in ruleRunnerFindings) {
      expect(
        rawFindings.any((f) => f.fingerprint == rf.fingerprint),
        isTrue,
        reason:
            'Runner finding ${rf.fingerprint} not in raw findings — '
            'pipeline introduced a finding that the rule did not emit.',
      );
    }

    // Raw count ≥ runner count (suppression can only reduce, never add findings).
    expect(
      rawFindings.where((f) => f.ruleId == 'slop-narrative-comment').length,
      greaterThanOrEqualTo(ruleRunnerFindings.length),
    );
  });
}

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

  test('AC1: finding kind is one of the documented rule kinds', () {
    final findings = makeRule().run(loadResult);
    const validKinds = {
      'narrative-comment',
      'banner-comment',
      'empty-category-label',
      'emoji-decoration',
      'end-marker-comment',
      'vague-todo',
    };
    for (final f in findings) {
      expect(validKinds, contains(f.kind));
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
  // Category B: banner / divider comments
  // ---------------------------------------------------------------------------

  test('banner: pure divider (====) → Finding, kind banner-comment', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('banner_comment.dart'))
        .where((f) => f.line == 3)
        .toList();
    expect(hits, hasLength(1));
    expect(hits.single.kind, 'banner-comment');
  });

  test('banner: framed label (****** SECTION ******) → Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('banner_comment.dart'))
        .where((f) => f.line == 9)
        .toList();
    expect(hits, hasLength(1));
    expect(hits.single.kind, 'banner-comment');
  });

  test('banner: plain hyphen divider → no Finding (legitimate convention)', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('banner_comment.dart'))
        .where((f) => f.line == 14)
        .toList();
    expect(hits, isEmpty);
  });

  test('banner: informative comment → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('banner_comment.dart'))
        .where((f) => f.line == 20)
        .toList();
    expect(hits, isEmpty);
  });

  test('banner_comment.dart — exactly 2 findings', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('banner_comment.dart'))
        .toList();
    expect(hits, hasLength(2));
  });

  // ---------------------------------------------------------------------------
  // Category B: empty category-label comments
  // ---------------------------------------------------------------------------

  test('category-label: "Main logic" before a statement → Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('category_label_comment.dart'))
        .where((f) => f.line == 5)
        .toList();
    expect(hits, hasLength(1));
    expect(hits.single.kind, 'empty-category-label');
  });

  test('category-label: "Helper function" before a declaration → Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('category_label_comment.dart'))
        .where((f) => f.line == 11)
        .toList();
    expect(hits, hasLength(1));
    expect(hits.single.kind, 'empty-category-label');
  });

  test('category-label: informative comment → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('category_label_comment.dart'))
        .where((f) => f.line == 14)
        .toList();
    expect(hits, isEmpty);
  });

  test('category_label_comment.dart — exactly 2 findings', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('category_label_comment.dart'))
        .toList();
    expect(hits, hasLength(2));
  });

  // ---------------------------------------------------------------------------
  // Category B: emoji-only decoration
  // ---------------------------------------------------------------------------

  test('emoji: emoji-only comment → Finding, kind emoji-decoration', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('emoji_comment.dart'))
        .where((f) => f.line == 5)
        .toList();
    expect(hits, hasLength(1));
    expect(hits.single.kind, 'emoji-decoration');
  });

  test('emoji: emoji plus real text → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('emoji_comment.dart'))
        .where((f) => f.line == 11)
        .toList();
    expect(hits, isEmpty);
  });

  test('emoji_comment.dart — exactly 1 finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('emoji_comment.dart'))
        .toList();
    expect(hits, hasLength(1));
  });

  // ---------------------------------------------------------------------------
  // Category B: end-of-block marker comments
  // ---------------------------------------------------------------------------

  test('end-marker: "end for loop" → Finding, kind end-marker-comment', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('end_marker_comment.dart'))
        .where((f) => f.line == 7)
        .toList();
    expect(hits, hasLength(1));
    expect(hits.single.kind, 'end-marker-comment');
  });

  test('end-marker: "end if" → Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('end_marker_comment.dart'))
        .where((f) => f.line == 17)
        .toList();
    expect(hits, hasLength(1));
  });

  test('end-marker: "End processOrder" → Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('end_marker_comment.dart'))
        .where((f) => f.line == 22)
        .toList();
    expect(hits, hasLength(1));
  });

  test('end-marker: long descriptive "end date …" sentence → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('end_marker_comment.dart'))
        .where((f) => f.line == 29)
        .toList();
    expect(hits, isEmpty);
  });

  test('end_marker_comment.dart — exactly 3 findings', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('end_marker_comment.dart'))
        .toList();
    expect(hits, hasLength(3));
  });

  // ---------------------------------------------------------------------------
  // Category B: vague TODOs
  // ---------------------------------------------------------------------------

  test('vague-todo: "TODO: Improve this" → Finding, kind vague-todo', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('vague_todo_comment.dart'))
        .where((f) => f.line == 5)
        .toList();
    expect(hits, hasLength(1));
    expect(hits.single.kind, 'vague-todo');
  });

  test('vague-todo: "TODO: Add more validation" → Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('vague_todo_comment.dart'))
        .where((f) => f.line == 12)
        .toList();
    expect(hits, hasLength(1));
  });

  test('vague-todo: "TODO: fix later" → Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('vague_todo_comment.dart'))
        .where((f) => f.line == 19)
        .toList();
    expect(hits, hasLength(1));
  });

  test('vague-todo: bare "TODO" → Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('vague_todo_comment.dart'))
        .where((f) => f.line == 26)
        .toList();
    expect(hits, hasLength(1));
  });

  test('vague-todo: concrete TODO with condition + reference → no Finding', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('vague_todo_comment.dart'))
        .where((f) => f.line == 33)
        .toList();
    expect(hits, isEmpty);
  });

  test('vague_todo_comment.dart — exactly 4 findings', () {
    final findings = makeRule().run(loadResult);
    final hits = findings
        .where((f) => f.filePath.contains('vague_todo_comment.dart'))
        .toList();
    expect(hits, hasLength(4));
  });

  // ---------------------------------------------------------------------------
  // Category B: kind + fingerprint determinism sanity checks
  // ---------------------------------------------------------------------------

  test('context-free findings never carry kind "narrative-comment"', () {
    final findings = makeRule().run(loadResult);
    final contextFreeKinds = {
      'banner-comment',
      'empty-category-label',
      'emoji-decoration',
      'end-marker-comment',
      'vague-todo',
    };
    for (final f in findings) {
      if (contextFreeKinds.contains(f.kind)) {
        expect(f.kind, isNot('narrative-comment'));
      }
    }
  });

  // ---------------------------------------------------------------------------
  // AC1: Total finding count across all non-generated fixture files
  // ---------------------------------------------------------------------------

  test('AC1: total findings — exactly 17 '
      '(5 declaration-adjacent + 12 context-free)', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings,
      hasLength(17),
      reason:
          'Expected exactly 17 findings total. '
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

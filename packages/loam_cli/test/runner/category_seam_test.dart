@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../support/shared_store.dart';

/// Category-seam tests: verify that the accessibility-category infrastructure
/// introduced in Issue 01 (a11y-saeule-seam-command-optout) is correct.
///
/// These tests are registry-level (no project load required for most of them).
void main() {
  useSharedAnalyzerStore();

  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'unused_exports_fixture',
    ),
  );

  // ---------------------------------------------------------------------------
  // 1. activeIdsForCategory: category seam produces correct subsets
  // ---------------------------------------------------------------------------

  group('activeIdsForCategory', () {
    test('drift category contains all 5 current rules', () {
      final ids = AnalysisRunner.activeIdsForCategory(RuleCategory.drift);
      expect(
        ids,
        containsAll([
          'architecture-boundaries',
          'circular-dependencies',
          'code-duplicates',
          'complexity-hotspots',
          'unused-public-exports',
        ]),
      );
      expect(ids.length, 5);
    });

    test('accessibility category contains a11y-image-label', () {
      final ids = AnalysisRunner.activeIdsForCategory(
        RuleCategory.accessibility,
      );
      expect(ids, contains('a11y-image-label'));
    });

    test('slop category contains slop-unjustified-ignore', () {
      final ids = AnalysisRunner.activeIdsForCategory(RuleCategory.slop);
      expect(ids, contains('slop-unjustified-ignore'));
    });

    test('drift IDs are sorted lexicographically', () {
      final ids = AnalysisRunner.activeIdsForCategory(RuleCategory.drift);
      final sorted = List<String>.from(ids)..sort();
      expect(ids, equals(sorted));
    });

    test('accessibility IDs do not overlap with drift IDs', () {
      final drift = AnalysisRunner.activeIdsForCategory(
        RuleCategory.drift,
      ).toSet();
      final a11y = AnalysisRunner.activeIdsForCategory(
        RuleCategory.accessibility,
      ).toSet();
      expect(drift.intersection(a11y), isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // 2. scan default-on: all drift IDs are active with default config
  // ---------------------------------------------------------------------------

  test('activeRuleIdsForConfig default config includes all drift rules', () {
    final ids = AnalysisRunner.activeRuleIdsForConfig(
      const LoamConfig.defaults(),
    );
    expect(
      ids,
      containsAll([
        'circular-dependencies',
        'code-duplicates',
        'complexity-hotspots',
        'unused-public-exports',
      ]),
    );
  });

  test('activeRuleIdsForConfig default config includes accessibility rules', () {
    // With includeA11y: true (default), the accessibility category is included.
    // a11y-image-label must appear in the default scan.
    final withA11y = AnalysisRunner.activeRuleIdsForConfig(
      const LoamConfig.defaults(),
    );
    final noA11yConfig = LoamConfig(
      ruleToggles: const {},
      ignoreGlobs: const [],
      includeA11y: false,
    );
    final withoutA11y = AnalysisRunner.activeRuleIdsForConfig(noA11yConfig);
    // With a11y rules present, the sets differ: a11y-image-label is in
    // withA11y but not in withoutA11y.
    expect(withA11y, contains('a11y-image-label'));
    expect(withoutA11y, isNot(contains('a11y-image-label')));
  });

  // ---------------------------------------------------------------------------
  // 3 + 4. --no-a11y and `loam a11y` (categoryFilter) on one fixture. The
  // fixture has no Flutter Image calls, so the difference shows in
  // stats.rulesRun, not in the findings. One analysis per runner mode.
  // ---------------------------------------------------------------------------

  group('category selection on unused_exports_fixture', () {
    late AnalysisOutcome defaultOutcome;
    late AnalysisOutcome noA11yOutcome;
    late AnalysisOutcome a11yOnlyOutcome;

    setUpAll(() async {
      defaultOutcome = await AnalysisRunner().analyze(fixturePath);
      noA11yOutcome = await AnalysisRunner(
        config: LoamConfig(
          ruleToggles: const {},
          ignoreGlobs: const [],
          includeA11y: false,
        ),
      ).analyze(fixturePath);
      a11yOnlyOutcome = await AnalysisRunner(
        config: const LoamConfig.defaults(),
        categoryFilter: RuleCategory.accessibility,
      ).analyze(fixturePath);
    });

    test('--no-a11y drops a11y-image-label from rulesRun only', () {
      expect(defaultOutcome.stats.rulesRun, contains('a11y-image-label'));
      expect(noA11yOutcome.stats.rulesRun, isNot(contains('a11y-image-label')));
      expect(
        noA11yOutcome.findings.map((f) => f.fingerprint).toList(),
        equals(defaultOutcome.findings.map((f) => f.fingerprint).toList()),
      );
    });

    test('accessibility filter runs a11y rules and finds nothing here', () {
      expect(a11yOnlyOutcome.stats.rulesRun, contains('a11y-image-label'));
      expect(a11yOnlyOutcome.findings, isEmpty);
      expect(
        defaultOutcome.findings,
        isNotEmpty,
        reason: 'fixture should have drift findings to confirm scan ran',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // 5. rulesetVersionForCategory: empty a11y set produces a stable version
  // ---------------------------------------------------------------------------

  test(
    'rulesetVersionForCategory for empty accessibility set is deterministic',
    () {
      final v1 = AnalysisRunner.rulesetVersionForCategory(
        RuleCategory.accessibility,
        const LoamConfig.defaults(),
      );
      final v2 = AnalysisRunner.rulesetVersionForCategory(
        RuleCategory.accessibility,
        const LoamConfig.defaults(),
      );
      expect(v1, equals(v2));
      expect(v1, startsWith('ruleset@'));
    },
  );

  test(
    'rulesetVersionForCategory for drift differs from accessibility set',
    () {
      final driftVersion = AnalysisRunner.rulesetVersionForCategory(
        RuleCategory.drift,
        const LoamConfig.defaults(),
      );
      final a11yVersion = AnalysisRunner.rulesetVersionForCategory(
        RuleCategory.accessibility,
        const LoamConfig.defaults(),
      );
      // Drift has 4 rules, accessibility has 1 — hashes must differ.
      expect(driftVersion, isNot(equals(a11yVersion)));
    },
  );
}

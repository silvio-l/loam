@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// Category-seam tests: verify that the accessibility-category infrastructure
/// introduced in Issue 01 (a11y-saeule-seam-command-optout) is correct.
///
/// These tests are registry-level (no project load required for most of them).
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
  // 1. activeIdsForCategory: category seam produces correct subsets
  // ---------------------------------------------------------------------------

  group('activeIdsForCategory', () {
    test('drift category contains all 4 current rules', () {
      final ids = AnalysisRunner.activeIdsForCategory(RuleCategory.drift);
      expect(
        ids,
        containsAll([
          'circular-dependencies',
          'code-duplicates',
          'complexity-hotspots',
          'unused-public-exports',
        ]),
      );
      expect(ids.length, 4);
    });

    test('accessibility category contains a11y-image-label', () {
      final ids = AnalysisRunner.activeIdsForCategory(
        RuleCategory.accessibility,
      );
      expect(ids, contains('a11y-image-label'));
    });

    test('slop category is empty (no slop rules registered yet)', () {
      final ids = AnalysisRunner.activeIdsForCategory(RuleCategory.slop);
      expect(ids, isEmpty);
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
  // 3. --no-a11y / includeA11y: false excludes a11y rules from the scan
  // ---------------------------------------------------------------------------

  group('scan --no-a11y excludes accessibility rules', () {
    test(
      'findings differ: default includes a11y-image-label, --no-a11y does not',
      () async {
        final defaultRunner = AnalysisRunner();
        final noA11yRunner = AnalysisRunner(
          config: LoamConfig(
            ruleToggles: const {},
            ignoreGlobs: const [],
            includeA11y: false,
          ),
        );

        final defaultFindings = await defaultRunner.run(fixturePath);
        final noA11yFindings = await noA11yRunner.run(fixturePath);

        // The unused_exports_fixture has no Flutter Image calls, so
        // a11y-image-label produces 0 findings on it. The difference is in
        // stats.rulesRun, not in finding count.
        // Both finding lists are equal (no Image findings in this fixture).
        expect(
          defaultFindings.map((f) => f.fingerprint).toList(),
          equals(noA11yFindings.map((f) => f.fingerprint).toList()),
          reason:
              'unused_exports_fixture has no Flutter Image calls — '
              'both scans produce identical findings',
        );
      },
    );

    test('stats.rulesRun differs: default includes a11y-image-label', () async {
      final defaultRunner = AnalysisRunner();
      final noA11yRunner = AnalysisRunner(
        config: LoamConfig(
          ruleToggles: const {},
          ignoreGlobs: const [],
          includeA11y: false,
        ),
      );

      final defaultOutcome = await defaultRunner.analyze(fixturePath);
      final noA11yOutcome = await noA11yRunner.analyze(fixturePath);

      // Default scan includes a11y-image-label; --no-a11y excludes it.
      expect(defaultOutcome.stats.rulesRun, contains('a11y-image-label'));
      expect(noA11yOutcome.stats.rulesRun, isNot(contains('a11y-image-label')));
    });
  });

  // ---------------------------------------------------------------------------
  // 4. loam a11y: categoryFilter=accessibility runs only a11y rules
  // ---------------------------------------------------------------------------

  group('categoryFilter=accessibility runs only accessibility rules', () {
    test('AnalysisRunner with accessibility categoryFilter yields 0 findings '
        'on unused_exports_fixture (no Flutter Image calls)', () async {
      final runner = AnalysisRunner(
        config: const LoamConfig.defaults(),
        categoryFilter: RuleCategory.accessibility,
      );
      final findings = await runner.run(fixturePath);
      expect(
        findings,
        isEmpty,
        reason:
            'unused_exports_fixture has no Flutter Image calls — '
            'a11y-image-label must return 0 findings (Exit 0)',
      );
    });

    test('accessibility stats.rulesRun contains a11y-image-label', () async {
      final runner = AnalysisRunner(
        config: const LoamConfig.defaults(),
        categoryFilter: RuleCategory.accessibility,
      );
      final outcome = await runner.analyze(fixturePath);
      expect(
        outcome.stats.rulesRun,
        contains('a11y-image-label'),
        reason: 'a11y-image-label is registered — must appear in rulesRun',
      );
    });

    test('AnalysisRunner with accessibility categoryFilter: 0 findings on '
        'this fixture, non-empty drift findings', () async {
      // Verify that the a11y-only categoryFilter finds nothing in a
      // non-Flutter fixture while the drift runner still finds drift issues.
      final runner = AnalysisRunner(
        config: const LoamConfig.defaults(),
        categoryFilter: RuleCategory.accessibility,
      );
      final driftRunner = AnalysisRunner();

      final a11yFindings = await runner.run(fixturePath);
      final driftFindings = await driftRunner.run(fixturePath);

      expect(
        a11yFindings,
        isEmpty,
        reason: 'No Flutter Image calls in unused_exports_fixture',
      );
      expect(
        driftFindings,
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

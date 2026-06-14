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

    test('accessibility category is empty (no a11y rules registered yet)', () {
      final ids = AnalysisRunner.activeIdsForCategory(
        RuleCategory.accessibility,
      );
      expect(ids, isEmpty);
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

  test('activeRuleIdsForConfig default config includes accessibility '
      '(currently empty, but category is not excluded)', () {
    // With includeA11y: true (default), the accessibility category is not
    // filtered. Since there are no a11y rules yet, the result is the same as
    // fullRegistryIds — no more, no less.
    final withA11y = AnalysisRunner.activeRuleIdsForConfig(
      const LoamConfig.defaults(),
    );
    final noA11yConfig = LoamConfig(
      ruleToggles: const {},
      ignoreGlobs: const [],
      includeA11y: false,
    );
    final withoutA11y = AnalysisRunner.activeRuleIdsForConfig(noA11yConfig);
    // When there are no a11y rules, both sets are identical.
    expect(withA11y, equals(withoutA11y));
  });

  // ---------------------------------------------------------------------------
  // 3. --no-a11y / includeA11y: false is bit-identical to default scan
  //    (since no a11y rules exist yet)
  // ---------------------------------------------------------------------------

  group(
    'scan --no-a11y is bit-identical when accessibility category is empty',
    () {
      test(
        'findings are identical between default and includeA11y:false',
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

          expect(
            defaultFindings.map((f) => f.fingerprint).toList(),
            equals(noA11yFindings.map((f) => f.fingerprint).toList()),
            reason:
                'With no a11y rules, --no-a11y must be bit-identical to default scan',
          );
        },
      );

      test(
        'stats.rulesRun is identical between default and includeA11y:false',
        () async {
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

          expect(
            defaultOutcome.stats.rulesRun,
            equals(noA11yOutcome.stats.rulesRun),
            reason: 'With no a11y rules, rulesRun must be identical',
          );
        },
      );
    },
  );

  // ---------------------------------------------------------------------------
  // 4. loam a11y: categoryFilter=accessibility returns 0 findings (Exit 0)
  // ---------------------------------------------------------------------------

  group('categoryFilter=accessibility returns 0 findings', () {
    test(
      'AnalysisRunner with accessibility categoryFilter yields 0 findings',
      () async {
        final runner = AnalysisRunner(
          categoryFilter: RuleCategory.accessibility,
        );
        final findings = await runner.run(fixturePath);
        expect(
          findings,
          isEmpty,
          reason:
              'No accessibility rules are registered yet — loam a11y must '
              'return 0 findings (Exit 0)',
        );
      },
    );

    test('accessibility stats.rulesRun is empty', () async {
      final runner = AnalysisRunner(categoryFilter: RuleCategory.accessibility);
      final outcome = await runner.analyze(fixturePath);
      expect(
        outcome.stats.rulesRun,
        isEmpty,
        reason: 'No accessibility rules exist yet',
      );
    });

    test('AnalysisRunner with accessibility categoryFilter: 0 findings on '
        'any fixture', () async {
      // Verify the invariant holds regardless of how many drift findings exist.
      final runner = AnalysisRunner(categoryFilter: RuleCategory.accessibility);
      final driftRunner = AnalysisRunner();

      final a11yFindings = await runner.run(fixturePath);
      final driftFindings = await driftRunner.run(fixturePath);

      expect(a11yFindings, isEmpty);
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
    'rulesetVersionForCategory for drift differs from empty accessibility set',
    () {
      final driftVersion = AnalysisRunner.rulesetVersionForCategory(
        RuleCategory.drift,
        const LoamConfig.defaults(),
      );
      final a11yVersion = AnalysisRunner.rulesetVersionForCategory(
        RuleCategory.accessibility,
        const LoamConfig.defaults(),
      );
      // Drift has 4 rules, accessibility has 0 — hashes must differ.
      expect(driftVersion, isNot(equals(a11yVersion)));
    },
  );
}

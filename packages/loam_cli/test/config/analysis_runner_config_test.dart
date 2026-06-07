@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
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
  // AC5 + AC6: rulesetVersion interaction — toggle changes version
  // ---------------------------------------------------------------------------

  test('fullRegistryIds contains unused-public-exports', () {
    expect(AnalysisRunner.fullRegistryIds, contains('unused-public-exports'));
  });

  test(
    'rulesetVersion with all rules enabled equals default rulesetVersion',
    () {
      final defaultVersion = AnalysisRunner.rulesetVersion;
      final configVersion = AnalysisRunner.rulesetVersionForConfig(
        const LoamConfig.defaults(),
      );
      expect(configVersion, equals(defaultVersion));
    },
  );

  test('disabling a rule via config changes rulesetVersion', () {
    final defaultVersion = AnalysisRunner.rulesetVersion;
    final config = LoamConfig(
      ruleToggles: {'unused-public-exports': false},
      ignoreGlobs: const [],
    );
    final configVersion = AnalysisRunner.rulesetVersionForConfig(config);
    // Toggling a rule changes activeRuleIds → different hash → different version
    expect(configVersion, isNot(equals(defaultVersion)));
  });

  test('activeRuleIdsForConfig excludes disabled rules', () {
    final config = LoamConfig(
      ruleToggles: {'unused-public-exports': false},
      ignoreGlobs: const [],
    );
    final ids = AnalysisRunner.activeRuleIdsForConfig(config);
    expect(ids, isNot(contains('unused-public-exports')));
  });

  test('activeRuleIdsForConfig includes all rules when none disabled', () {
    final ids = AnalysisRunner.activeRuleIdsForConfig(
      const LoamConfig.defaults(),
    );
    expect(ids, containsAll(['unused-public-exports']));
  });

  // ---------------------------------------------------------------------------
  // AC4: A disabled rule produces no findings
  // ---------------------------------------------------------------------------

  test('disabled rule produces no findings', () async {
    final config = LoamConfig(
      ruleToggles: {'unused-public-exports': false},
      ignoreGlobs: const [],
    );
    final runner = AnalysisRunner(config: config);
    final findings = await runner.run(fixturePath);
    // unused-public-exports is the only rule — disabling it means 0 findings
    expect(findings, isEmpty);
  });

  test('enabled rule (default config) produces findings in fixture', () async {
    final runner = AnalysisRunner();
    final findings = await runner.run(fixturePath);
    expect(findings, isNotEmpty);
  });

  // ---------------------------------------------------------------------------
  // AC7: scan/gate/baseline use same config-aware runner path (no second path)
  // ---------------------------------------------------------------------------

  test(
    'AnalysisRunner without config equals AnalysisRunner with defaults config',
    () async {
      final runner1 = AnalysisRunner();
      final runner2 = AnalysisRunner(config: const LoamConfig.defaults());
      final findings1 = await runner1.run(fixturePath);
      final findings2 = await runner2.run(fixturePath);
      expect(
        findings1.map((f) => f.fingerprint).toList(),
        equals(findings2.map((f) => f.fingerprint).toList()),
      );
    },
  );
}

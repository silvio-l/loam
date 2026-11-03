@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/config_loader.dart';
import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/rules/rule_profile.dart';
import 'package:loam/src/rules/slop_assertion_free_test_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture_packages.dart';
import '../support/shared_store.dart';

void main() {
  useSharedAnalyzerStore();

  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'slop_assertion_free_test_fixture',
    ),
  );

  late ProjectLoadResult loadResult;

  setUpAll(() async {
    await ensureFixtureResolved(fixturePath);
    loadResult = await const ProjectLoader().load(fixturePath);
    expect(
      loadResult.errors,
      isEmpty,
      reason: loadResult.errors.map((e) => '${e.path}: ${e.reason}').join('; '),
    );
  });

  final rule = SlopAssertionFreeTestRule(projectRoot: fixturePath);

  Map<String, int> perFile(List<Finding> findings) => {
    for (final path in findings.map((f) => f.filePath).toSet())
      path: findings.where((f) => f.filePath == path).length,
  };

  test('rule contract: id, category, strict profile, info severity', () {
    expect(rule.ruleId, 'slop-assertion-free-test');
    expect(rule.category, RuleCategory.slop);
    expect(kRuleProfiles['slop-assertion-free-test'], RuleProfile.strict);
  });

  test('reports exactly the tests that never assert', () {
    final findings = rule.run(loadResult);
    // flagged_cases.dart holds a helper chain of four hops (flagged, 'too
    // deep'); clean_cases.dart: expect, helpers up to 3 hops, verify, fail, throw,
    // closures, skip and the inline suppression (applied later) are all fine.
    expect(perFile(findings), {
      'test/flagged_cases.dart': 8,
      'test/cycle_cases.dart': 1,
      'test/configured_cases.dart': 1,
      'test/clean_cases.dart': 1, // the inline-suppressed test (applied later)
    });
    expect(findings.every((f) => f.kind == 'assertion-free-test'), isTrue);
    expect(findings.every((f) => f.severity == Severity.info), isTrue);
    // The same description twice in one scope still gets distinct prints.
    expect(findings.map((f) => f.fingerprint).toSet(), hasLength(11));
  });

  test('fingerprints are stable across runs', () {
    final a = rule.run(loadResult).map((f) => f.fingerprint).toList();
    final b = rule.run(loadResult).map((f) => f.fingerprint).toList();
    expect(a, b);
  });

  test('a configured assertion function releases the tests that use it', () {
    final configured = SlopAssertionFreeTestRule(
      projectRoot: fixturePath,
      assertionFunctions: const ['assertHealthy'],
    );
    expect(perFile(configured.run(loadResult)), {
      'test/flagged_cases.dart': 8,
      'test/cycle_cases.dart': 1,
      'test/clean_cases.dart': 1,
    });
  });

  test(
    'loam.yaml: assertion_functions are read, unknown keys rejected',
    () async {
      final dir = Directory.systemTemp.createTempSync('loam_afr');
      addTearDown(() => dir.deleteSync(recursive: true));
      Directory(p.join(dir.path, '.git')).createSync();
      File(p.join(dir.path, 'loam.yaml')).writeAsStringSync(
        'slop_assertion_free_test:\n  assertion_functions: [expectGolden]\n',
      );
      final config = await ConfigLoader.load(dir.path);
      expect(config.assertionFunctions, ['expectGolden']);

      File(p.join(dir.path, 'loam.yaml')).writeAsStringSync(
        'slop_assertion_free_test:\n  assertion_function: [x]\n',
      );
      expect(
        () => ConfigLoader.load(dir.path),
        throwsA(isA<ConfigLoadException>()),
      );
    },
  );

  test(
    'runner: findings survive, inline suppression and config apply',
    () async {
      AnalysisRunner runner(List<String> functions) => AnalysisRunner(
        config: LoamConfig(
          ruleToggles: const {},
          ignoreGlobs: const [],
          assertionFunctions: functions,
        ),
      );

      final plain = await runner(const []).analyze(fixturePath);
      final mine = plain.findings.where(
        (f) => f.ruleId == 'slop-assertion-free-test',
      );
      // 11 raw findings; the one in clean_cases.dart carries a loam-ignore.
      expect(mine, hasLength(10));
      expect(plain.suppressedCount, 1);
      expect(mine.any((f) => f.filePath == 'test/clean_cases.dart'), isFalse);

      final listed = await runner(const ['assertHealthy']).analyze(fixturePath);
      expect(
        listed.findings.where((f) => f.ruleId == 'slop-assertion-free-test'),
        hasLength(9),
      );
    },
  );
}

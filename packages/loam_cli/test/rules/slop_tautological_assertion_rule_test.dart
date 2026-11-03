@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/rules/rule_profile.dart';
import 'package:loam/src/rules/slop_tautological_assertion_rule.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/cli_runner.dart';
import '../support/fixture_packages.dart';
import '../support/shared_store.dart';

void main() {
  useSharedAnalyzerStore();

  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'slop_tautological_assertion_fixture',
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

  final rule = SlopTautologicalAssertionRule(projectRoot: fixturePath);

  test('rule contract: id, category, core profile', () {
    expect(rule.ruleId, 'slop-tautological-assertion');
    expect(rule.category, RuleCategory.slop);
    expect(kRuleProfiles['slop-tautological-assertion'], RuleProfile.core);
  });

  test('reports exactly the tautologies, as warnings', () {
    final findings = rule.run(loadResult);
    expect(findings.map((f) => f.filePath).toSet(), {
      'lib/flagged_assertions.dart',
      'lib/suppressed_assertion.dart',
      'test/regular_test.dart',
    });
    expect(findings, hasLength(12));
    expect(findings.every((f) => f.severity == Severity.warning), isTrue);
    expect(findings.every((f) => f.kind == 'tautological-assertion'), isTrue);
    expect(findings.map((f) => f.fingerprint).toSet(), hasLength(12));
  });

  test('identical calls in one member get distinct, stable fingerprints', () {
    final a = rule.run(loadResult).map((f) => f.fingerprint).toList();
    final b = rule.run(loadResult).map((f) => f.fingerprint).toList();
    expect(a, b);
  });

  test(
    'CLI: the finding is reported and the inline suppression honoured',
    () async {
      final result = await runCli([
        'scan',
        '--project-root',
        fixturePath,
        '--format',
        'json',
      ]);
      expect(result.stdout, contains('slop-tautological-assertion'));
      expect(result.stdout, contains('flagged_assertions.dart'));
      expect(result.stdout, isNot(contains('suppressed_assertion.dart')));
      expect(result.stdout, isNot(contains('clean_assertions.dart')));
    },
  );
}

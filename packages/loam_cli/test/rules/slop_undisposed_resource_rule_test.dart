@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/rules/rule_profile.dart';
import 'package:loam/src/rules/slop_undisposed_resource_rule.dart';
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
      'slop_undisposed_resource_fixture',
    ),
  );

  late ProjectLoadResult loadResult;

  setUpAll(() async {
    await ensureFixtureResolved(fixturePath);
    await ensureFixtureResolved(p.join(fixturePath, '..', 'flutter_stub'));
    loadResult = await const ProjectLoader().load(fixturePath);
    expect(
      loadResult.errors,
      isEmpty,
      reason: loadResult.errors.map((e) => '${e.path}: ${e.reason}').join('; '),
    );
  });

  final rule = SlopUndisposedResourceRule(projectRoot: fixturePath);

  test('rule contract: id, category, strict profile', () {
    expect(rule.ruleId, 'slop-undisposed-resource');
    expect(rule.category, RuleCategory.slop);
    expect(kRuleProfiles['slop-undisposed-resource'], RuleProfile.strict);
  });

  test('reports exactly the fields that are created but never released', () {
    final findings = rule.run(loadResult);
    final names = findings
        .map((f) => RegExp(r'`(\w+)`').firstMatch(f.message)!.group(1))
        .toList();
    expect(
      names,
      unorderedEquals([
        '_name',
        '_focus',
        '_tick',
        '_level',
        '_notifier',
        '_level',
        '_events',
        '_text',
        '_controller',
        '_level',
      ]),
    );
    expect(findings.map((f) => f.filePath).toSet(), {
      'lib/flagged.dart',
      'lib/mic_probe.dart',
      'lib/suppressed.dart',
    });
    expect(findings.every((f) => f.severity == Severity.warning), isTrue);
    expect(findings.every((f) => f.kind == 'undisposed-resource'), isTrue);
    expect(findings.map((f) => f.fingerprint).toSet(), hasLength(10));
  });

  test('findings and fingerprints are deterministic', () {
    final a = rule.run(loadResult).map((f) => f.fingerprint).toList();
    final b = rule.run(loadResult).map((f) => f.fingerprint).toList();
    expect(a, b);
  });

  test('CLI: reported under the strict profile, inline suppression '
      'honoured', () async {
    final result = await runCli([
      'scan',
      '--project-root',
      fixturePath,
      '--format',
      'json',
    ]);
    final reported = [
      for (final f in (jsonDecode(result.stdout) as Map)['findings'] as List)
        if ((f as Map)['ruleId'] == 'slop-undisposed-resource')
          f['filePath'] as String,
    ];
    expect(reported, hasLength(9));
    expect(reported.toSet(), {'lib/flagged.dart', 'lib/mic_probe.dart'});
  });
}

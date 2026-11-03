@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/rules/rule_profile.dart';
import 'package:loam/src/rules/slop_setstate_after_async_gap_rule.dart';
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
      'slop_setstate_after_async_gap_fixture',
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

  final rule = SlopSetStateAfterAsyncGapRule(projectRoot: fixturePath);

  test('rule contract: id, category, strict profile', () {
    expect(rule.ruleId, 'slop-setstate-after-async-gap');
    expect(rule.category, RuleCategory.slop);
    expect(kRuleProfiles['slop-setstate-after-async-gap'], RuleProfile.strict);
  });

  test('reports setState after an unguarded async gap, nothing else', () {
    final findings = rule.run(loadResult);
    final flagged = findings
        .where((f) => f.filePath == 'lib/flagged_setstate.dart')
        .map((f) => f.line)
        .toList();
    // One per method of _CounterState: after await, then, whenComplete, in
    // try, in catch, in finally, this.setState after a guard that precedes
    // the await, await in the if condition, await for, async closure,
    // await in an early-exit condition, await after the guard.
    expect(flagged, [17, 21, 26, 33, 43, 51, 58, 63, 69, 76, 83, 90]);
    expect(findings.map((f) => f.filePath).toSet(), {
      'lib/flagged_setstate.dart',
      'lib/suppressed_setstate.dart',
    });
    expect(findings.every((f) => f.severity == Severity.warning), isTrue);
    expect(findings.map((f) => f.fingerprint).toSet(), hasLength(13));
  });

  test('fingerprints are stable across runs', () {
    final a = rule.run(loadResult).map((f) => f.fingerprint).toList();
    final b = rule.run(loadResult).map((f) => f.fingerprint).toList();
    expect(a, b);
  });

  test(
    'CLI: strict scan reports it and honours the inline suppression',
    () async {
      final result = await runCli([
        'scan',
        '--project-root',
        fixturePath,
        '--format',
        'json',
      ]);
      final report = jsonDecode(result.stdout) as Map<String, Object?>;
      final files = [
        for (final f in report['findings']! as List<Object?>)
          if (f case {
            'ruleId': 'slop-setstate-after-async-gap',
            'filePath': final Object path,
          })
            path,
      ];
      expect(files.toSet(), {'lib/flagged_setstate.dart'});
      expect(files, hasLength(12));
    },
  );
}

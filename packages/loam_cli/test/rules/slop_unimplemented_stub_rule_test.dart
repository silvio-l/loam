@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/rules/slop_unimplemented_stub_rule.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture_packages.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'slop_unimplemented_stub_fixture',
    ),
  );

  late ProjectLoadResult loadResult;
  late List<Finding> findings;

  setUpAll(() async {
    await ensureFixtureResolved(fixturePath);
    loadResult = await const ProjectLoader().load(fixturePath);
    expect(loadResult.errors, isEmpty);
    findings = SlopUnimplementedStubRule(
      projectRoot: fixturePath,
    ).run(loadResult);
  });

  test('rule identity and category', () {
    const rule = SlopUnimplementedStubRule(projectRoot: '.');
    expect(rule.ruleId, 'slop-unimplemented-stub');
    expect(SlopUnimplementedStubRule.ruleIdStatic, rule.ruleId);
    expect(rule.category, RuleCategory.slop);
  });

  test('flags stub methods, getters, setters and top-level functions', () {
    final hits = findings.where((f) => f.filePath == 'lib/stubs.dart');
    expect(hits.map((f) => f.line), [6, 9, 14, 17, 21]);
    for (final f in hits) {
      expect(f.kind, 'unimplemented-stub');
      expect(f.severity, Severity.warning);
      expect(f.remedy, isNotEmpty);
    }
  });

  test('getter and setter of the same name get distinct fingerprints', () {
    final stubs = findings.where((f) => f.filePath == 'lib/stubs.dart');
    expect(stubs.map((f) => f.fingerprint).toSet(), hasLength(5));
  });

  test('follows a PlatformInterface chain across files by hint', () {
    for (final f in [
      'foo_platform_interface.dart',
      'method_channel_foo.dart',
      'hinted_by_import.dart',
    ]) {
      expect(findings.where((x) => x.filePath == 'lib/$f'), isEmpty, reason: f);
    }
    final foreign = findings.where(
      (x) => x.filePath == 'lib/foreign_stub.dart',
    );
    expect(foreign, hasLength(1));
    expect(foreign.single.fingerprint, isNotEmpty);
  });

  test('ignores templates, partial bodies, other errors and shadow types', () {
    expect(findings.where((f) => f.filePath == 'lib/legit.dart'), isEmpty);
  });

  test('ignores generated files and files outside the source dirs', () {
    expect(
      findings.map((f) => f.filePath),
      isNot(contains('lib/generated.g.dart')),
    );
    expect(findings.where((f) => f.filePath.startsWith('test/')), isEmpty);
  });

  test('a custom source dir list moves the scope', () {
    final inTest = SlopUnimplementedStubRule(
      projectRoot: fixturePath,
      sourceDirs: const ['test'],
    ).run(loadResult);
    expect(inTest.map((f) => f.filePath), ['test/fake_test_support.dart']);
  });
}

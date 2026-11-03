@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/rules/slop_placeholder_comment_rule.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture_packages.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'slop_placeholder_comment_fixture',
    ),
  );

  late List<Finding> findings;

  setUpAll(() async {
    await ensureFixtureResolved(fixturePath);
    final result = await const ProjectLoader().load(fixturePath);
    expect(result.errors, isEmpty);
    findings = SlopPlaceholderCommentRule(projectRoot: fixturePath).run(result);
  });

  test('rule identity and category', () {
    const rule = SlopPlaceholderCommentRule(projectRoot: '.');
    expect(rule.ruleId, 'slop-placeholder-comment');
    expect(SlopPlaceholderCommentRule.ruleIdStatic, rule.ruleId);
    expect(rule.category, RuleCategory.slop);
  });

  test('flags every placeholder phrase variant, one finding each', () {
    final hits = findings
        .where((f) => f.filePath == 'lib/placeholders.dart')
        .toList();
    expect(hits.map((f) => f.line), [7, 12, 17, 22, 27, 32]);
    for (final f in hits) {
      expect(f.kind, 'placeholder-comment');
      expect(f.severity, Severity.warning);
      expect(f.remedy, isNotEmpty);
    }
  });

  test('does not flag prose, dartdoc, strings or a bare ellipsis', () {
    expect(findings.where((f) => f.filePath == 'lib/legit.dart'), isEmpty);
  });

  test('skips generated files', () {
    expect(findings.where((f) => f.filePath.endsWith('.g.dart')), isEmpty);
  });

  test('every finding has its own fingerprint', () {
    expect(findings.map((f) => f.fingerprint).toSet(), hasLength(6));
  });
}

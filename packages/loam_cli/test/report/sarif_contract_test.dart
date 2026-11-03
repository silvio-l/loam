@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:loam/src/baseline/baseline.dart';
import 'package:loam/src/baseline/baseline_diff.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/recommendation/recommendation_engine.dart';
import 'package:loam/src/report/reporter.dart';
import 'package:loam/src/report/sarif_reporter.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Finding _f(String id, Severity s, int line, String fp) => Finding(
  ruleId: id,
  severity: s,
  filePath: '/project/lib/a.dart',
  line: line,
  message: 'm',
  fingerprint: fp,
);

ReportPayload _payload(List<Finding> findings, {BaselineDiff? diff}) =>
    ReportPayload(
      findings: findings,
      projectRoot: '/project',
      rulesetVersion: 'ruleset@x',
      toolVersion: '0.0.0',
      isTty: false,
      baselineDiff: diff,
    );

Map<String, dynamic> _render(ReportPayload payload) =>
    jsonDecode(const SarifReporter().render(payload)) as Map<String, dynamic>;

void main() {
  final fresh = _f('slop-empty-catch', Severity.warning, 3, 'fp-new');
  final kept = _f('circular-dependencies', Severity.error, 8, 'fp-kept');
  final fixed = const BaselineFinding(
    fingerprint: 'fp-fixed',
    ruleId: 'unused-public-exports',
    filePath: 'lib/gone.dart',
    line: 4,
    message: 'gone',
  );
  final diff = BaselineDiff(
    newFindings: [fresh],
    keptFindings: [kept],
    fixedFindings: [fixed],
  );

  test(
    'validates against the SARIF 2.1.0 schema, with and without baseline',
    () {
      final schema = JsonSchema.create(
        jsonDecode(
              File(
                p.join(
                  Directory.current.path,
                  'test',
                  'fixtures',
                  'sarif',
                  'sarif-schema-2.1.0.json',
                ),
              ).readAsStringSync(),
            )
            as Map<String, dynamic>,
      );
      for (final payload in [
        _payload([fresh, kept]),
        _payload([fresh, kept], diff: diff),
      ]) {
        final result = schema.validate(_render(payload));
        expect(result.isValid, isTrue, reason: result.errors.join('\n'));
      }
    },
  );

  test('every result carries the finding fingerprint and a rule index', () {
    final run = (_render(_payload([fresh, kept]))['runs'] as List).single;
    final rules = run['tool']['driver']['rules'] as List;
    for (final r in run['results'] as List) {
      expect(r['partialFingerprints'], isNotEmpty);
      expect(rules[r['ruleIndex'] as int]['id'], r['ruleId']);
    }
    final fps = (run['results'] as List)
        .map((r) => (r['partialFingerprints'] as Map).values.single)
        .toSet();
    expect(fps, {'fp-new', 'fp-kept'});
  });

  test('every rule has help text; known rules carry the guidance corpus', () {
    final run = (_render(_payload([fresh, kept]))['runs'] as List).single;
    for (final r in run['tool']['driver']['rules'] as List) {
      expect((r['help']['text'] as String), isNotEmpty);
      expect(r['help']['text'], kGuidanceCorpus[r['id']]);
    }
  });

  test('rules catalog is sorted by id regardless of finding order', () {
    List<String> ids(List<Finding> fs) =>
        ((_render(_payload(fs))['runs'] as List)
                    .single['tool']['driver']['rules']
                as List)
            .map((r) => r['id'] as String)
            .toList();
    expect(ids([fresh, kept]), ['circular-dependencies', 'slop-empty-catch']);
    expect(ids([kept, fresh]), ['circular-dependencies', 'slop-empty-catch']);
  });

  test('baselineState: new, unchanged and absent for fixed entries', () {
    final run =
        (_render(_payload([fresh, kept], diff: diff))['runs'] as List).single;
    final state = {
      for (final r in run['results'] as List)
        (r['partialFingerprints'] as Map).values.single: r['baselineState'],
    };
    expect(state, {
      'fp-new': 'new',
      'fp-kept': 'unchanged',
      'fp-fixed': 'absent',
    });
    final rules = run['tool']['driver']['rules'] as List;
    for (final r in run['results'] as List) {
      expect(rules[r['ruleIndex'] as int]['id'], r['ruleId']);
    }
  });

  test('no baselineState without a baseline comparison', () {
    final run = (_render(_payload([fresh, kept]))['runs'] as List).single;
    for (final r in run['results'] as List) {
      expect(r.containsKey('baselineState'), isFalse);
    }
  });

  test('severity maps to level and location is present', () {
    final run = (_render(_payload([fresh, kept]))['runs'] as List).single;
    final byFp = {
      for (final r in run['results'] as List)
        (r['partialFingerprints'] as Map).values.single: r,
    };
    expect(byFp['fp-kept']['level'], 'error');
    expect(byFp['fp-new']['level'], 'warning');
    final loc = byFp['fp-new']['locations'][0]['physicalLocation'];
    expect(loc['artifactLocation']['uri'], 'lib/a.dart');
    expect(loc['region']['startLine'], 3);
  });
}

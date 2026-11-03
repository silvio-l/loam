@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:loam/src/baseline/baseline_engine.dart';
import 'package:loam/src/model/finding.dart';
import 'package:test/test.dart';

Finding _f(String fp, String rule, String file, int line, String msg) =>
    Finding(
      ruleId: rule,
      severity: Severity.warning,
      filePath: file,
      line: line,
      message: msg,
      fingerprint: fp,
    );

/// Issue #3: baselines written with the old index-based fingerprints must not
/// turn the ratchet gate red after the scheme change.
void main() {
  late Directory tmp;
  late BaselineEngine engine;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('loam_baseline_migration_');
    engine = BaselineEngine(projectRoot: tmp.path);
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  void writeLegacy(List<Map<String, Object>> findings) {
    File('${tmp.path}/baseline.json').writeAsStringSync(
      jsonEncode({
        'schemaVersion': 1,
        'rulesetVersion': 'ruleset@x',
        'findings': findings,
      }),
    );
  }

  Map<String, Object> legacy(String fp, int line, String msg) => {
    'fingerprint': fp,
    'ruleId': 'slop-empty-catch',
    'filePath': 'lib/a.dart',
    'line': line,
    'message': msg,
  };

  test('write() stamps the current fingerprint scheme', () {
    engine.write([_f('aa', 'r', 'lib/a.dart', 1, 'm')], 'ruleset@x');
    final b = engine.read();
    expect(b.fingerprintScheme, currentFingerprintScheme);
    expect(b.isLegacyScheme, isFalse);
  });

  test('legacy baseline is read as legacy scheme', () {
    writeLegacy([legacy('old1', 3, 'm')]);
    expect(engine.read().isLegacyScheme, isTrue);
  });

  test('legacy entries pair with changed fingerprints: nothing new/fixed', () {
    writeLegacy([legacy('old1', 3, 'm'), legacy('old2', 9, 'm')]);
    final diff = engine.diff([
      _f('new1', 'slop-empty-catch', 'lib/a.dart', 5, 'm'),
      _f('new2', 'slop-empty-catch', 'lib/a.dart', 11, 'm'),
    ], engine.read());
    expect(diff.newFindings, isEmpty);
    expect(diff.fixedFindings, isEmpty);
    expect(diff.keptFindings, hasLength(2));
  });

  test('a genuinely new finding on a legacy baseline is still new', () {
    writeLegacy([legacy('old1', 3, 'm')]);
    final diff = engine.diff([
      _f('new1', 'slop-empty-catch', 'lib/a.dart', 5, 'm'),
      _f('new2', 'slop-empty-catch', 'lib/a.dart', 20, 'm'),
      _f('new3', 'slop-empty-catch', 'lib/b.dart', 1, 'm'),
    ], engine.read());
    expect(diff.keptFindings, hasLength(1));
    expect(diff.newFindings, hasLength(2));
  });

  test('a fixed legacy finding is reported fixed', () {
    writeLegacy([legacy('old1', 3, 'm'), legacy('old2', 9, 'other')]);
    final diff = engine.diff([
      _f('new1', 'slop-empty-catch', 'lib/a.dart', 5, 'm'),
    ], engine.read());
    expect(diff.fixedFindings.map((f) => f.fingerprint), ['old2']);
    expect(diff.newFindings, isEmpty);
  });

  test('legacy: one fixed and a differing new finding in the same file', () {
    writeLegacy([legacy('old1', 3, 'm'), legacy('old2', 9, 'm')]);
    // old2 was fixed; a new finding with a different message appeared.
    final diff = engine.diff([
      _f('new1', 'slop-empty-catch', 'lib/a.dart', 5, 'm'),
      _f('new9', 'slop-empty-catch', 'lib/a.dart', 30, 'brand new'),
    ], engine.read());
    expect(diff.newFindings.map((f) => f.fingerprint), ['new9']);
    expect(diff.fixedFindings.map((f) => f.fingerprint), ['old2']);
    expect(diff.keptFindings, hasLength(1));
  });

  test('current-scheme baselines use exact fingerprints only', () {
    engine.write([_f('aa', 'r', 'lib/a.dart', 1, 'm')], 'ruleset@x');
    final diff = engine.diff([
      _f('bb', 'r', 'lib/a.dart', 1, 'm'),
    ], engine.read());
    expect(diff.newFindings, hasLength(1));
    expect(diff.fixedFindings, hasLength(1));
  });

  test('prune on a legacy baseline drops only unmatched entries and keeps the '
      'legacy scheme', () {
    writeLegacy([legacy('old1', 3, 'm'), legacy('old2', 9, 'm')]);
    final baseline = engine.read();
    final diff = engine.diff([
      _f('new1', 'slop-empty-catch', 'lib/a.dart', 5, 'm'),
    ], baseline);
    expect(engine.prune(baseline, diff.fixedFindings), 1);
    final after = engine.read();
    expect(after.findings.map((f) => f.fingerprint), ['old1']);
    expect(after.isLegacyScheme, isTrue);
  });
}

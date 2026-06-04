@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/rules/unused_public_exports_rule.dart';
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

  late ProjectLoadResult loadResult;

  setUpAll(() async {
    final loader = ProjectLoader();
    loadResult = await loader.load(fixturePath);
    expect(loadResult.errors, isEmpty, reason: 'Fixture must load cleanly');
  });

  UnusedPublicExportsRule makeRule() =>
      UnusedPublicExportsRule(projectRoot: fixturePath);

  // ---------------------------------------------------------------------------
  // AC1: Rule implements Rule interface and ruleId is correct
  // ---------------------------------------------------------------------------
  test('ruleId is unused-public-exports', () {
    expect(makeRule().ruleId, 'unused-public-exports');
  });

  // ---------------------------------------------------------------------------
  // AC2: Unused public classes are reported as Findings
  // ---------------------------------------------------------------------------
  test('unused public class UnusedClass is reported', () {
    final findings = makeRule().run(loadResult);
    final reported = findings.map((f) => f.message).toList();
    expect(
      reported.any((m) => m.contains('UnusedClass')),
      isTrue,
      reason: 'UnusedClass must appear in findings',
    );
  });

  test('unused public class AnotherUnusedClass is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('AnotherUnusedClass')),
      isTrue,
    );
  });

  // ---------------------------------------------------------------------------
  // AC3: Cross-file referenced class is NOT reported
  // ---------------------------------------------------------------------------
  test('cross-file referenced class UsedClass is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('UsedClass')),
      isFalse,
      reason: 'UsedClass is referenced from consumer.dart — must not appear',
    );
  });

  // ---------------------------------------------------------------------------
  // AC4: Test-only referenced class is NOT reported
  // ---------------------------------------------------------------------------
  test('test-only referenced class TestOnlyClass is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('TestOnlyClass')),
      isFalse,
      reason: 'TestOnlyClass is used in test/ — must not appear',
    );
  });

  // ---------------------------------------------------------------------------
  // AC4b: Tool-only referenced class is NOT reported
  // ---------------------------------------------------------------------------
  test('tool-only referenced class ToolOnlyClass is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('ToolOnlyClass')),
      isFalse,
      reason: 'ToolOnlyClass is used in tool/ — must not appear',
    );
  });

  // ---------------------------------------------------------------------------
  // AC5: Private class is NOT reported
  // ---------------------------------------------------------------------------
  test('private class _PrivateClass is never in findings', () {
    final findings = makeRule().run(loadResult);
    expect(findings.any((f) => f.message.contains('_PrivateClass')), isFalse);
  });

  // ---------------------------------------------------------------------------
  // AC5b: main function is NOT reported
  // ---------------------------------------------------------------------------
  test('main entrypoint is never reported', () {
    final findings = makeRule().run(loadResult);
    expect(findings.any((f) => f.message.contains('`main`')), isFalse);
  });

  // ---------------------------------------------------------------------------
  // AC6: Each Finding has the correct ruleId
  // ---------------------------------------------------------------------------
  test('all findings carry ruleId = unused-public-exports', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      expect(f.ruleId, 'unused-public-exports');
    }
  });

  // ---------------------------------------------------------------------------
  // AC7: Each Finding has a non-empty, 16-char fingerprint
  // ---------------------------------------------------------------------------
  test('each finding has non-empty 16-char fingerprint', () {
    final findings = makeRule().run(loadResult);
    expect(findings, isNotEmpty);
    for (final f in findings) {
      expect(f.fingerprint, isNotEmpty);
      expect(f.fingerprint.length, 16);
    }
  });

  // ---------------------------------------------------------------------------
  // AC7b: One finding per symbol (no duplicates)
  // ---------------------------------------------------------------------------
  test('exactly one finding per unused symbol', () {
    final findings = makeRule().run(loadResult);
    final symbols = findings.map((f) => f.message).toList();
    final unique = symbols.toSet();
    expect(
      symbols.length,
      equals(unique.length),
      reason: 'No duplicate findings expected',
    );
  });

  // ---------------------------------------------------------------------------
  // AC8: Two runs over the same code return identical findings (determinism)
  // ---------------------------------------------------------------------------
  test('two runs produce identical findings in identical order', () {
    final findings1 = makeRule().run(loadResult);
    final findings2 = makeRule().run(loadResult);

    expect(findings1.length, equals(findings2.length));
    for (var i = 0; i < findings1.length; i++) {
      expect(
        findings1[i].fingerprint,
        equals(findings2[i].fingerprint),
        reason: 'Fingerprint at index $i must match',
      );
      expect(
        findings1[i].message,
        equals(findings2[i].message),
        reason: 'Message at index $i must match',
      );
    }
  });

  // ---------------------------------------------------------------------------
  // AC9: Finding message mentions symbol name and kind
  // ---------------------------------------------------------------------------
  test('finding message contains symbol name and kind', () {
    final findings = makeRule().run(loadResult);
    for (final f in findings) {
      // Message should contain the kind word and the symbol name in backticks.
      expect(
        f.message,
        matches(r'unused public \w+ `\w+`'),
        reason:
            'Message "${f.message}" must match "unused public <kind> `<name>`"',
      );
    }
  });

  // ---------------------------------------------------------------------------
  // AC10: Rule does not crash when ProjectLoadResult.errors is non-empty
  // ---------------------------------------------------------------------------
  test('rule does not crash on non-empty errors list', () {
    final resultWithErrors = ProjectLoadResult(
      resolved: loadResult.resolved,
      errors: const [
        LoadFileError(path: '/fake/broken.dart', reason: 'broken'),
      ],
    );
    final findings = makeRule().run(resultWithErrors);
    // Must return a list (possibly empty) without throwing.
    expect(findings, isA<List<dynamic>>());
  });

  // ---------------------------------------------------------------------------
  // AC10b: Rule handles empty ProjectLoadResult without crash
  // ---------------------------------------------------------------------------
  test('rule returns empty list for empty ProjectLoadResult', () {
    const emptyResult = ProjectLoadResult(resolved: [], errors: []);
    final findings = makeRule().run(emptyResult);
    expect(findings, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // AC11: Fingerprint is position-robust (same anchor → same fingerprint)
  // ---------------------------------------------------------------------------
  test('fingerprint is stable across runs (same inputs → same hash)', () {
    final findings1 = makeRule().run(loadResult);
    final findings2 = makeRule().run(loadResult);
    for (var i = 0; i < findings1.length; i++) {
      expect(findings1[i].fingerprint, findings2[i].fingerprint);
    }
  });
}

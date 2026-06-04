@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/baseline/baseline_engine.dart';
import 'package:loam/src/model/finding.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Finding _finding(String fingerprint, {int line = 10}) => Finding(
  ruleId: 'unused-public-exports',
  severity: Severity.warning,
  filePath: 'lib/src/foo.dart',
  line: line,
  message: 'Unused export: Foo',
  fingerprint: fingerprint,
);

void main() {
  late Directory tempDir;
  late BaselineEngine engine;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('loam_diff_test_');
    engine = BaselineEngine(projectRoot: tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  // ---------------------------------------------------------------------------
  // AC1: BaselineEngine.diff classifies new / kept / fixed via fingerprint
  // ---------------------------------------------------------------------------

  group('BaselineEngine.diff()', () {
    test('finding in both current and baseline → kept', () {
      engine.write([_finding('fp-alpha')], 'ruleset@1');
      final baseline = engine.read();
      final diff = engine.diff([_finding('fp-alpha')], baseline);

      expect(diff.keptFindings, hasLength(1));
      expect(diff.newFindings, isEmpty);
      expect(diff.fixedFindings, isEmpty);
    });

    test('finding in current only → new', () {
      engine.write([], 'ruleset@1');
      final baseline = engine.read();
      final diff = engine.diff([_finding('fp-new')], baseline);

      expect(diff.newFindings, hasLength(1));
      expect(diff.keptFindings, isEmpty);
      expect(diff.fixedFindings, isEmpty);
    });

    test('finding in baseline only (not in current) → fixed', () {
      engine.write([_finding('fp-fixed')], 'ruleset@1');
      final baseline = engine.read();
      final diff = engine.diff([], baseline);

      expect(diff.fixedFindings, hasLength(1));
      expect(diff.newFindings, isEmpty);
      expect(diff.keptFindings, isEmpty);
    });

    test('line-shift stays kept (fingerprint is position-robust)', () {
      // Write baseline with line=10
      engine.write([_finding('fp-stable', line: 10)], 'ruleset@1');
      final baseline = engine.read();
      // Current has same fingerprint but line shifted to 42
      final diff = engine.diff([_finding('fp-stable', line: 42)], baseline);

      expect(
        diff.keptFindings,
        hasLength(1),
        reason: 'line-shift must stay kept',
      );
      expect(diff.newFindings, isEmpty);
      expect(diff.fixedFindings, isEmpty);
    });

    test('mixed: new + kept + fixed classified correctly', () {
      engine.write([
        _finding('fp-kept'),
        _finding('fp-will-be-fixed'),
      ], 'ruleset@1');
      final baseline = engine.read();

      final diff = engine.diff([
        _finding('fp-kept'),
        _finding('fp-new'),
      ], baseline);

      expect(diff.keptFindings.map((f) => f.fingerprint), contains('fp-kept'));
      expect(diff.newFindings.map((f) => f.fingerprint), contains('fp-new'));
      expect(
        diff.fixedFindings.map((f) => f.fingerprint),
        contains('fp-will-be-fixed'),
      );
    });

    test('empty current + empty baseline → all three lists empty', () {
      engine.write([], 'ruleset@1');
      final baseline = engine.read();
      final diff = engine.diff([], baseline);

      expect(diff.newFindings, isEmpty);
      expect(diff.keptFindings, isEmpty);
      expect(diff.fixedFindings, isEmpty);
    });
  });
}

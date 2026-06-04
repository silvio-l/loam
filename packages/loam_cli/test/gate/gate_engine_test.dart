@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/baseline/baseline_engine.dart';
import 'package:loam/src/gate/gate_engine.dart';
import 'package:loam/src/model/finding.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

Finding _finding(String fingerprint) => Finding(
  ruleId: 'unused-public-exports',
  severity: Severity.warning,
  filePath: 'lib/src/foo.dart',
  line: 10,
  message: 'Unused export: Foo',
  fingerprint: fingerprint,
);

void main() {
  late Directory tempDir;
  late BaselineEngine engine;
  const gate = GateEngine();

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('loam_gate_test_');
    engine = BaselineEngine(projectRoot: tempDir.path);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  // ---------------------------------------------------------------------------
  // AC2: GateEngine.evaluate(mode: ratchet)
  // ---------------------------------------------------------------------------

  group('GateEngine.evaluate(mode: ratchet)', () {
    test('only kept findings → passed=true, exitCode=0', () {
      engine.write([_finding('fp-legacy')], 'ruleset@1');
      final baseline = engine.read();
      final diff = engine.diff([_finding('fp-legacy')], baseline);

      final result = gate.evaluate(diff: diff, mode: GateMode.ratchet);

      expect(result.passed, isTrue);
      expect(result.exitCode, equals(0));
    });

    test('only fixed findings → passed=true, exitCode=0', () {
      engine.write([_finding('fp-was-there')], 'ruleset@1');
      final baseline = engine.read();
      // Current is empty → fp-was-there is fixed
      final diff = engine.diff([], baseline);

      final result = gate.evaluate(diff: diff, mode: GateMode.ratchet);

      expect(result.passed, isTrue);
      expect(result.exitCode, equals(0));
    });

    test('at least one new finding → passed=false, exitCode=1', () {
      engine.write([], 'ruleset@1');
      final baseline = engine.read();
      final diff = engine.diff([_finding('fp-brand-new')], baseline);

      final result = gate.evaluate(diff: diff, mode: GateMode.ratchet);

      expect(result.passed, isFalse);
      expect(result.exitCode, equals(1));
    });

    test('new + kept mixed → passed=false, exitCode=1', () {
      engine.write([_finding('fp-legacy')], 'ruleset@1');
      final baseline = engine.read();
      final diff = engine.diff([
        _finding('fp-legacy'),
        _finding('fp-new'),
      ], baseline);

      final result = gate.evaluate(diff: diff, mode: GateMode.ratchet);

      expect(result.passed, isFalse);
      expect(result.exitCode, equals(1));
    });

    test('result counts are correct', () {
      engine.write([_finding('fp-kept'), _finding('fp-fixed')], 'ruleset@1');
      final baseline = engine.read();
      final diff = engine.diff([
        _finding('fp-kept'),
        _finding('fp-new'),
      ], baseline);

      final result = gate.evaluate(diff: diff, mode: GateMode.ratchet);

      expect(result.newCount, equals(1));
      expect(result.keptCount, equals(1));
      expect(result.fixedCount, equals(1));
    });

    test('empty diff → passed=true, exitCode=0, all counts zero', () {
      engine.write([], 'ruleset@1');
      final baseline = engine.read();
      final diff = engine.diff([], baseline);

      final result = gate.evaluate(diff: diff, mode: GateMode.ratchet);

      expect(result.passed, isTrue);
      expect(result.exitCode, equals(0));
      expect(result.newCount, equals(0));
      expect(result.keptCount, equals(0));
      expect(result.fixedCount, equals(0));
    });
  });

  // ---------------------------------------------------------------------------
  // AC1: GateEngine.evaluate(mode: absolute, threshold)
  // ---------------------------------------------------------------------------

  group('GateEngine.evaluate(mode: absolute)', () {
    test('no findings, threshold=0 → passed=true, exitCode=0', () {
      final result = gate.evaluate(mode: GateMode.absolute, findings: []);

      expect(result.passed, isTrue);
      expect(result.exitCode, equals(0));
    });

    test('1 finding, default threshold=0 → passed=false, exitCode=1', () {
      final result = gate.evaluate(
        mode: GateMode.absolute,
        findings: [_finding('fp-1')],
      );

      expect(result.passed, isFalse);
      expect(result.exitCode, equals(1));
    });

    test('2 findings, threshold=2 → passed=true (≤ threshold)', () {
      final result = gate.evaluate(
        mode: GateMode.absolute,
        findings: [_finding('fp-1'), _finding('fp-2')],
        threshold: 2,
      );

      expect(result.passed, isTrue);
      expect(result.exitCode, equals(0));
    });

    test('3 findings, threshold=2 → passed=false (> threshold)', () {
      final result = gate.evaluate(
        mode: GateMode.absolute,
        findings: [_finding('fp-1'), _finding('fp-2'), _finding('fp-3')],
        threshold: 2,
      );

      expect(result.passed, isFalse);
      expect(result.exitCode, equals(1));
    });

    test('newCount reflects total findings count in absolute mode', () {
      final result = gate.evaluate(
        mode: GateMode.absolute,
        findings: [_finding('fp-1'), _finding('fp-2')],
        threshold: 5,
      );

      expect(result.newCount, equals(2));
      expect(result.keptCount, equals(0));
      expect(result.fixedCount, equals(0));
    });

    test('absolute mode does not require a diff (diff defaults to null)', () {
      // Verifies signature: diff is optional when using absolute mode.
      expect(
        () => gate.evaluate(mode: GateMode.absolute, findings: []),
        returnsNormally,
      );
    });
  });
}

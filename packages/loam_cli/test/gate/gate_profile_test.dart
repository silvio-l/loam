@TestOn('vm')
library;

import 'package:loam/src/baseline/baseline_diff.dart';
import 'package:loam/src/gate/gate_engine.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/rules/rule_profile.dart';
import 'package:test/test.dart';

Finding _finding(String ruleId, String fingerprint) => Finding(
  ruleId: ruleId,
  severity: Severity.warning,
  filePath: 'lib/a.dart',
  line: 1,
  message: 'm',
  fingerprint: fingerprint,
);

void main() {
  const gate = GateEngine();
  final coreNew = _finding('slop-empty-catch', 'fp-core');
  final strictNew = _finding('code-duplicates', 'fp-strict');

  BaselineDiff diffOf(List<Finding> news) => BaselineDiff(
    newFindings: news,
    keptFindings: const [],
    fixedFindings: const [],
  );

  group('ratchet with profile', () {
    test('core: a new strict-rule finding is a hint, the gate stays green', () {
      final r = gate.evaluate(
        mode: GateMode.ratchet,
        diff: diffOf([strictNew]),
        profile: RuleProfile.core,
      );
      expect(r.passed, isTrue);
      expect(r.newCount, 0);
      expect(r.advisoryCount, 1);
    });

    test('core: a new core-rule finding still turns the gate red', () {
      final r = gate.evaluate(
        mode: GateMode.ratchet,
        diff: diffOf([coreNew, strictNew]),
        profile: RuleProfile.core,
      );
      expect(r.passed, isFalse);
      expect(r.newCount, 1);
      expect(r.advisoryCount, 1);
    });

    test('strict: the same strict-rule finding blocks', () {
      final r = gate.evaluate(
        mode: GateMode.ratchet,
        diff: diffOf([strictNew]),
        profile: RuleProfile.strict,
      );
      expect(r.passed, isFalse);
      expect(r.advisoryCount, 0);
    });

    test('no profile → nothing filtered', () {
      final r = gate.evaluate(
        mode: GateMode.ratchet,
        diff: diffOf([strictNew]),
      );
      expect(r.passed, isFalse);
    });
  });

  group('absolute with profile', () {
    test('core counts only core-rule findings against the threshold', () {
      final r = gate.evaluate(
        mode: GateMode.absolute,
        findings: [coreNew, strictNew, strictNew],
        profile: RuleProfile.core,
      );
      expect(r.newCount, 1);
      expect(r.advisoryCount, 2);
      expect(r.passed, isFalse);
    });

    test('core with only strict-rule findings passes', () {
      final r = gate.evaluate(
        mode: GateMode.absolute,
        findings: [strictNew],
        profile: RuleProfile.core,
      );
      expect(r.passed, isTrue);
    });
  });
}

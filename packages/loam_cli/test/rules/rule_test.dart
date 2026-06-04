import 'package:loam/loam.dart';
import 'package:test/test.dart';

/// Minimal dummy [Rule] that satisfies the interface contract.
///
/// Returns a single [Finding] whose fingerprint is computed via
/// [computeFingerprint] — demonstrating integration between the Rule interface
/// and the Fingerprint sprint artefact.
class _DummyRule implements Rule {
  @override
  String get ruleId => 'dummy-rule';

  @override
  List<Finding> run(ProjectLoadResult result) {
    final fingerprint = computeFingerprint(
      ruleId: ruleId,
      relativePath: 'lib/src/example.dart',
      semanticAnchor: 'ExampleClass',
    );
    return [
      Finding(
        ruleId: ruleId,
        severity: Severity.info,
        filePath: 'lib/src/example.dart',
        line: 1,
        message: 'Dummy finding.',
        fingerprint: fingerprint,
      ),
    ];
  }
}

void main() {
  group('Rule interface', () {
    test(
      'DummyRule implements Rule and returns ≥1 Finding with non-empty fingerprint',
      () {
        final rule = _DummyRule();
        final result = const ProjectLoadResult(resolved: [], errors: []);

        expect(rule.ruleId, 'dummy-rule');

        final findings = rule.run(result);
        expect(findings, isNotEmpty);

        final finding = findings.first;
        expect(finding.fingerprint, isNotEmpty);
        expect(finding.fingerprint.length, 16);
      },
    );

    test('DummyRule fingerprint is stable across calls', () {
      final rule = _DummyRule();
      final result = const ProjectLoadResult(resolved: [], errors: []);

      final findings1 = rule.run(result);
      final findings2 = rule.run(result);

      expect(findings1.first.fingerprint, findings2.first.fingerprint);
    });
  });
}

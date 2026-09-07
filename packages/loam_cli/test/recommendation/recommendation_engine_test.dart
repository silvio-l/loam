@TestOn('vm')
library;

import 'package:loam/src/model/finding.dart';
import 'package:loam/src/recommendation/recommendation_engine.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Shared fixture helpers
// ---------------------------------------------------------------------------

Finding _finding({
  required String ruleId,
  String filePath = 'lib/src/foo.dart',
  int line = 1,
  String message = 'message',
  String fingerprint = 'fp',
}) => Finding(
  ruleId: ruleId,
  severity: Severity.warning,
  filePath: filePath,
  line: line,
  message: message,
  fingerprint: fingerprint,
);

void main() {
  group('RecommendationEngine (pure, no I/O, no LLM)', () {
    test('0 findings ⇒ empty recommendation list (no empty-run noise)', () {
      final result = const RecommendationEngine().recommend(const []);
      expect(result, isEmpty);
    });

    test('a single fired rule produces exactly one recommendation', () {
      final findings = [_finding(ruleId: 'unused-public-exports')];
      final result = const RecommendationEngine().recommend(findings);
      expect(result, hasLength(1));
      expect(result.single.ruleId, 'unused-public-exports');
      expect(result.single.guidance, isNotEmpty);
    });

    test('a rule that fired many times still produces exactly one '
        'recommendation (deduplicated)', () {
      final findings = List.generate(
        40,
        (i) => _finding(
          ruleId: 'unused-public-exports',
          line: i + 1,
          fingerprint: 'fp$i',
        ),
      );
      final result = const RecommendationEngine().recommend(findings);
      expect(result, hasLength(1));
      expect(result.single.ruleId, 'unused-public-exports');
    });

    test('multiple distinct fired rules produce one recommendation each, '
        'sorted lexicographically by ruleId regardless of finding order', () {
      final findings = [
        _finding(ruleId: 'unused-public-exports'),
        _finding(ruleId: 'slop-empty-catch'),
        _finding(ruleId: 'circular-dependencies'),
      ];
      final result = const RecommendationEngine().recommend(findings);
      expect(result.map((r) => r.ruleId).toList(), [
        'circular-dependencies',
        'slop-empty-catch',
        'unused-public-exports',
      ]);
    });

    test('deterministic: same findings (any input order) ⇒ same recommendation '
        'list in the same order', () {
      final a = [
        _finding(ruleId: 'unused-public-exports'),
        _finding(ruleId: 'slop-empty-catch'),
      ];
      final b = [
        _finding(ruleId: 'slop-empty-catch', fingerprint: 'other'),
        _finding(ruleId: 'unused-public-exports', fingerprint: 'other2'),
      ];
      final resultA = const RecommendationEngine().recommend(a);
      final resultB = const RecommendationEngine().recommend(b);
      expect(
        resultA.map((r) => r.ruleId).toList(),
        resultB.map((r) => r.ruleId).toList(),
      );
      expect(
        resultA.map((r) => r.guidance).toList(),
        resultB.map((r) => r.guidance).toList(),
      );
    });

    test('a ruleId absent from the corpus is skipped, not crashed on', () {
      final findings = [_finding(ruleId: 'not-a-real-rule')];
      final result = const RecommendationEngine().recommend(findings);
      expect(result, isEmpty);
    });
  });

  group('Guidance corpus completeness', () {
    test('every ruleId in AnalysisRunner.fullRegistryIds has a non-empty '
        'guidance entry — no fired rule class is left without prevention '
        'guidance', () {
      for (final ruleId in AnalysisRunner.fullRegistryIds) {
        final guidance = kGuidanceCorpus[ruleId];
        expect(
          guidance,
          isNotNull,
          reason: '$ruleId is missing from kGuidanceCorpus',
        );
        expect(
          guidance,
          isNotEmpty,
          reason: '$ruleId has an empty guidance entry',
        );
      }
    });

    test('kGuidanceVersion is a non-empty version marker', () {
      expect(kGuidanceVersion, isNotEmpty);
      expect(kGuidanceVersion, startsWith('guidance@'));
    });
  });
}

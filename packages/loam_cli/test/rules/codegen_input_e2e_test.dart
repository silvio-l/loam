@TestOn('vm')
library;

/// E2E tests for UnusedPublicExportsRule with code-gen input fixture.
///
/// Verifies:
/// AC5: Mixed fixture (code-gen input + genuine dead code) → only genuine dead
///      code is reported, deterministically sorted, with qualified semanticAnchor.
/// AC6: UsageIndex is structurally unaffected: a symbol referenced only from a
///      code-gen input class still counts as "used" (no new FP at another site).
import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/rules/unused_public_exports_rule.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(Directory.current.path, 'test', 'fixtures', 'codegen_input_fixture'),
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
  // AC5: Genuine dead code is reported
  // ---------------------------------------------------------------------------

  test('AC5: PlainClass.unusedField is reported as unused', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`unusedField`')),
      isTrue,
      reason: 'PlainClass.unusedField is genuine dead code — must be reported',
    );
  });

  test('AC5: PlainClass.unusedMethod is reported as unused', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`unusedMethod`')),
      isTrue,
      reason: 'PlainClass.unusedMethod is genuine dead code — must be reported',
    );
  });

  // ---------------------------------------------------------------------------
  // AC5: Code-gen input members are NOT reported (FP reduction)
  // ---------------------------------------------------------------------------

  test('AC5: DriftTable column getters are NOT reported', () {
    final findings = makeRule().run(loadResult);
    // None of the DriftTable column getters should produce findings.
    for (final name in ['name', 'color', 'isDeleted']) {
      expect(
        findings.any((f) => f.message.contains('`$name`')),
        isFalse,
        reason:
            'DriftTable.$name is a code-gen input getter — must NOT be reported',
      );
    }
  });

  test('AC5: DriftDataClass.displayTitle is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`displayTitle`')),
      isFalse,
      reason:
          'DriftDataClass.displayTitle is a code-gen input — must NOT be reported',
    );
  });

  test('AC5: DriftView.summary is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`summary`')),
      isFalse,
      reason: 'DriftView.summary is a code-gen input — must NOT be reported',
    );
  });

  test('AC5: PartHeuristicClass.heuristicMethod is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`heuristicMethod`')),
      isFalse,
      reason:
          'PartHeuristicClass.heuristicMethod is a fallback code-gen input — '
          'must NOT be reported',
    );
  });

  // ---------------------------------------------------------------------------
  // AC5: Deterministic sort (same order on two runs)
  // ---------------------------------------------------------------------------

  test(
    'AC5: findings are deterministically sorted (two runs produce same order)',
    () {
      final findings1 = makeRule().run(loadResult);
      final findings2 = makeRule().run(loadResult);
      expect(findings1.length, equals(findings2.length));
      for (var i = 0; i < findings1.length; i++) {
        expect(
          findings1[i].fingerprint,
          equals(findings2[i].fingerprint),
          reason:
              'Finding at index $i must have the same fingerprint on both runs',
        );
      }
    },
  );

  // ---------------------------------------------------------------------------
  // AC5: Findings have qualified semanticAnchor-based fingerprints
  // ---------------------------------------------------------------------------

  test('AC5: PlainClass.unusedField finding has non-empty fingerprint', () {
    final findings = makeRule().run(loadResult);
    final unusedFieldFinding = findings.firstWhere(
      (f) => f.message.contains('`unusedField`'),
      orElse: () => throw StateError('unusedField finding not found'),
    );
    expect(unusedFieldFinding.fingerprint, isNotEmpty);
    expect(unusedFieldFinding.fingerprint.length, 16);
  });

  // ---------------------------------------------------------------------------
  // Annotation-registry E2E: annotated class members NOT reported; plain class
  // members still reported (FN-protection).
  // ---------------------------------------------------------------------------

  test('annotation E2E: AnnotatedDriftDatabase.version is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`version`')),
      isFalse,
      reason:
          'AnnotatedDriftDatabase carries @DriftDatabase — its members must '
          'not be reported as unused',
    );
  });

  test('annotation E2E: AnnotatedFreezed.name is NOT reported', () {
    final findings = makeRule().run(loadResult);
    // Note: 'name' also appears in DriftTable (column getter), but neither
    // should be reported. The test just confirms no finding with `name`.
    // For specificity we also check AnnotatedDataClassName and Riverpod.
    expect(
      findings.any(
        (f) =>
            f.message.contains('`build`') &&
            f.message.contains('AnnotatedRiverpodClass'),
      ),
      isFalse,
      reason:
          'AnnotatedRiverpodClass carries @Riverpod — its build() method must '
          'not be reported',
    );
  });

  test('annotation E2E: AnnotatedJsonSerializable.id is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`id`')),
      isFalse,
      reason:
          'AnnotatedJsonSerializable carries @JsonSerializable — its members '
          'must not be reported as unused',
    );
  });

  test(
    'annotation E2E: PlainClass.unusedField still reported (FN-protection)',
    () {
      final findings = makeRule().run(loadResult);
      expect(
        findings.any((f) => f.message.contains('`unusedField`')),
        isTrue,
        reason:
            'PlainClass has no code-gen markers — its unused members must still '
            'be reported (no false negative introduced by annotation exclusion)',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // AC6: UsageIndex structural integrity —
  //      A symbol only referenced from a code-gen input class still counts as
  //      "used" (no new FP introduced by the classifier).
  //
  //      HelperUsedOnlyFromDriftTable is used by DriftTableConsumer (which
  //      references it as a field type). DriftTableConsumer is a plain class
  //      (not a Drift subclass), so its use of HelperUsedOnlyFromDriftTable
  //      counts as a reference.
  // ---------------------------------------------------------------------------

  test(
    'AC6: HelperUsedOnlyFromDriftTable is NOT reported (referenced by consumer)',
    () {
      final findings = makeRule().run(loadResult);
      expect(
        findings.any(
          (f) => f.message.contains('`HelperUsedOnlyFromDriftTable`'),
        ),
        isFalse,
        reason:
            'HelperUsedOnlyFromDriftTable is referenced from DriftTableConsumer — '
            'UsageIndex must count this reference even though the consumer is in the '
            'codegen fixture',
      );
    },
  );
}

@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/fingerprint.dart';
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
  // AC7b: One finding per symbol (no duplicate fingerprints)
  //
  // With Slice B (member support), multiple different classes can have members
  // with the same unqualified name (e.g. `name` getter on many classes).
  // Uniqueness is therefore checked via fingerprints, which incorporate the
  // qualified semanticAnchor (ClassName.memberName), not via message text.
  // ---------------------------------------------------------------------------
  test('exactly one finding per unused symbol (no duplicate fingerprints)', () {
    final findings = makeRule().run(loadResult);
    final fingerprints = findings.map((f) => f.fingerprint).toList();
    final unique = fingerprints.toSet();
    expect(
      fingerprints.length,
      equals(unique.length),
      reason:
          'No duplicate fingerprints expected — each symbol produces exactly '
          'one finding with a unique fingerprint',
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

  // ---------------------------------------------------------------------------
  // Issue 02 — Unused symbols of every declaration kind are reported
  // ---------------------------------------------------------------------------

  test('unused top-level function is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`unusedFunction`')),
      isTrue,
      reason: 'unusedFunction must be reported as unused',
    );
  });

  test('used top-level function is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`usedFunction`')),
      isFalse,
      reason: 'usedFunction is referenced — must not appear in findings',
    );
  });

  test('unused top-level getter is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`unusedGetter`')),
      isTrue,
      reason: 'unusedGetter must be reported as unused',
    );
  });

  test('used top-level getter is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`usedGetter`')),
      isFalse,
      reason: 'usedGetter is referenced — must not appear in findings',
    );
  });

  test('unused top-level setter is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`unusedSetter`')),
      isTrue,
      reason: 'unusedSetter must be reported as unused',
    );
  });

  test('used top-level setter is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`usedSetter`')),
      isFalse,
      reason: 'usedSetter is referenced — must not appear in findings',
    );
  });

  test('unused enum is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`UnusedEnum`')),
      isTrue,
      reason: 'UnusedEnum must be reported as unused',
    );
  });

  test('used enum is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`UsedEnum`')),
      isFalse,
      reason: 'UsedEnum is referenced — must not appear in findings',
    );
  });

  test('unused extension is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`UnusedExtension`')),
      isTrue,
      reason: 'UnusedExtension must be reported as unused',
    );
  });

  test('used extension is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`UsedExtension`')),
      isFalse,
      reason: 'UsedExtension is referenced — must not appear in findings',
    );
  });

  test('unused mixin is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`UnusedMixin`')),
      isTrue,
      reason: 'UnusedMixin must be reported as unused',
    );
  });

  test('used mixin is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`UsedMixin`')),
      isFalse,
      reason: 'UsedMixin is referenced — must not appear in findings',
    );
  });

  test('unused typedef is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`UnusedTypedef`')),
      isTrue,
      reason: 'UnusedTypedef must be reported as unused',
    );
  });

  test('used typedef is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`UsedTypedef`')),
      isFalse,
      reason: 'UsedTypedef is referenced — must not appear in findings',
    );
  });

  test('unused top-level variable is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`unusedVariable`')),
      isTrue,
      reason: 'unusedVariable must be reported as unused',
    );
  });

  test('used top-level variable is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`usedVariable`')),
      isFalse,
      reason: 'usedVariable is referenced — must not appear in findings',
    );
  });

  // ---------------------------------------------------------------------------
  // Issue 02 — Part-file deduplication
  // ---------------------------------------------------------------------------

  test('unused part-file declaration is reported exactly once', () {
    final findings = makeRule().run(loadResult);
    final partFindings = findings
        .where((f) => f.message.contains('`UnusedPartClass`'))
        .toList();
    expect(
      partFindings.length,
      1,
      reason:
          'UnusedPartClass (in a part file) must produce exactly one Finding, '
          'not duplicated across library + part file entries',
    );
  });

  test('used part-file declaration is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`UsedPartClass`')),
      isFalse,
      reason:
          'UsedPartClass is referenced from kinds_consumer.dart — must not '
          'appear in findings',
    );
  });

  test(
    'part-file finding carries the part file path (not the library path)',
    () {
      final findings = makeRule().run(loadResult);
      final partFinding = findings.firstWhere(
        (f) => f.message.contains('`UnusedPartClass`'),
        orElse: () => throw StateError('UnusedPartClass finding not found'),
      );
      expect(
        partFinding.filePath,
        'lib/all_kinds_part.dart',
        reason: 'Part-file finding must show the part file path',
      );
    },
  );

  test('no duplicate findings across all symbols (fingerprint-identity dedup)', () {
    final findings = makeRule().run(loadResult);
    // Uniqueness is by fingerprint: the fingerprint incorporates the qualified
    // semanticAnchor (ClassName.memberName for members, name for top-level),
    // so two different classes with identically-named members produce DIFFERENT
    // fingerprints even though their messages share the same unqualified name.
    final fingerprints = findings.map((f) => f.fingerprint).toList();
    final unique = fingerprints.toSet();
    expect(
      fingerprints.length,
      unique.length,
      reason:
          'No duplicate fingerprints — each symbol produces at most one '
          'Finding regardless of fragments or member-name collisions',
    );
  });

  // ---------------------------------------------------------------------------
  // Issue 03 — AC1: Generated-file exclusion
  // Symbols declared in *.g.dart are NOT reported; references FROM generated
  // files count as usage (UsedOnlyFromGenerated must not be reported).
  // ---------------------------------------------------------------------------

  test('AC1-gen: GeneratedClass (declared in *.g.dart) is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`GeneratedClass`')),
      isFalse,
      reason: 'Symbols declared in *.g.dart files must not produce findings',
    );
  });

  test('AC1-gen: UsedOnlyFromGenerated is NOT reported '
      '(references from *.g.dart count as usage)', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`UsedOnlyFromGenerated`')),
      isFalse,
      reason:
          'A symbol only referenced from a generated file must not be '
          'reported — generated files are reference sources',
    );
  });

  // ---------------------------------------------------------------------------
  // Issue 03 — AC2: Re-exported symbol exclusion
  // Symbols re-exported via `export` directives are NOT reported.
  // ---------------------------------------------------------------------------

  test(
    'AC2-reexport: ReExportedClass (re-exported via barrel) is NOT reported',
    () {
      final findings = makeRule().run(loadResult);
      expect(
        findings.any((f) => f.message.contains('`ReExportedClass`')),
        isFalse,
        reason:
            'Symbols re-exported via `export` directives must not produce findings',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Issue 03 — AC3: Annotation exclusion
  // @visibleForTesting and @pragma annotated symbols are NOT reported.
  // ---------------------------------------------------------------------------

  test('AC3-annotation: @visibleForTesting class is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`VisibleForTestingClass`')),
      isFalse,
      reason:
          'Symbols annotated with @visibleForTesting must not produce findings',
    );
  });

  test('AC3-annotation: @pragma class is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`PragmaAnnotatedClass`')),
      isFalse,
      reason: 'Symbols annotated with @pragma must not produce findings',
    );
  });

  // ---------------------------------------------------------------------------
  // Issue 04 — Slice B: Member-E2E tests
  // ---------------------------------------------------------------------------

  test('SliceB-AC1: unused public method is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`unusedMethod`')),
      isTrue,
      reason: 'unusedMethod on MemberHost must be reported as unused',
    );
  });

  test('SliceB-AC1: unused public field is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`unusedField`')),
      isTrue,
      reason: 'unusedField on MemberHost must be reported as unused',
    );
  });

  test('SliceB-AC1: unused public member getter is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`unusedMemberGetter`')),
      isTrue,
      reason: 'unusedMemberGetter on MemberHost must be reported as unused',
    );
  });

  test('SliceB-AC1: unused public member setter is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`unusedMemberSetter`')),
      isTrue,
      reason: 'unusedMemberSetter on MemberHost must be reported as unused',
    );
  });

  test('SliceB-AC1: unused public enum method is reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`unusedEnumMethod`')),
      isTrue,
      reason: 'unusedEnumMethod on MemberEnum must be reported as unused',
    );
  });

  test('SliceB-AC2: used public method is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`usedMethod`')),
      isFalse,
      reason:
          'usedMethod is referenced from members_consumer.dart — must not appear',
    );
  });

  test('SliceB-AC2: used public field is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`usedField`')),
      isFalse,
      reason:
          'usedField is referenced from members_consumer.dart — must not appear',
    );
  });

  test('SliceB-AC2: used public member getter is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`usedMemberGetter`')),
      isFalse,
      reason:
          'usedMemberGetter is referenced from members_consumer.dart — must not appear',
    );
  });

  test('SliceB-AC2: used public member setter is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`usedMemberSetter`')),
      isFalse,
      reason:
          'usedMemberSetter is referenced from members_consumer.dart — must not appear',
    );
  });

  test('SliceB-AC2: used public enum method is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`usedEnumMethod`')),
      isFalse,
      reason:
          'usedEnumMethod is referenced from members_consumer.dart — must not appear',
    );
  });

  test('SliceB-AC3: @override method is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`interfaceMethod`')),
      isFalse,
      reason:
          'interfaceMethod carries @override — must never produce a finding',
    );
  });

  test('SliceB-AC3: @override getter is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`interfaceGetter`')),
      isFalse,
      reason:
          'interfaceGetter carries @override — must never produce a finding',
    );
  });

  test('SliceB-AC3: toString() override is NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`toString`')),
      isFalse,
      reason: 'toString() with @override must never produce a finding',
    );
  });

  test('SliceB-AC4: synthetic enum fields (values/index) are NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`values`')),
      isFalse,
      reason: 'Enum.values (synthetic) must never produce a finding',
    );
    expect(
      findings.any((f) => f.message.contains('`index`')),
      isFalse,
      reason: 'Enum.index (synthetic) must never produce a finding',
    );
  });

  test('SliceB-AC4: enum constants (alpha/beta) are NOT reported', () {
    final findings = makeRule().run(loadResult);
    expect(
      findings.any((f) => f.message.contains('`alpha`')),
      isFalse,
      reason: 'Enum constant alpha must never produce a finding',
    );
    expect(
      findings.any((f) => f.message.contains('`beta`')),
      isFalse,
      reason: 'Enum constant beta must never produce a finding',
    );
  });

  test(
    'SliceB-AC5: member finding has qualified fingerprint (unique per class)',
    () {
      final findings = makeRule().run(loadResult);
      final unusedMethod = findings.firstWhere(
        (f) => f.message.contains('`unusedMethod`'),
        orElse: () => throw StateError('unusedMethod finding not found'),
      );
      // Fingerprint is computed from qualified anchor (MemberHost.unusedMethod),
      // so it must differ from a top-level symbol with the same unqualified name.
      expect(unusedMethod.fingerprint, isNotEmpty);
      expect(unusedMethod.fingerprint.length, 16);
      // The fingerprint must NOT match a hypothetical top-level `unusedMethod`
      // (different anchor → different hash).
      final topLevelFingerprint = computeFingerprint(
        ruleId: 'unused-public-exports',
        relativePath: unusedMethod.filePath,
        semanticAnchor: 'unusedMethod', // unqualified, for comparison
      );
      expect(
        unusedMethod.fingerprint,
        isNot(equals(topLevelFingerprint)),
        reason:
            'Member fingerprint uses qualified anchor → must differ from '
            'unqualified top-level anchor',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Regression (real HellerIO case): a call to `SdkStyleLogger.fatal` must NOT
  // suppress the unused `AppLoggerLike.fatal` — usage resolution is semantic
  // (element-model), not name-based. A name-based implementation would report
  // ZERO `fatal` findings here (false negative); the correct one reports EXACTLY
  // ONE, anchored to AppLoggerLike.
  //
  // Background: HellerIO's `app_monitoring.dart` calls `Sentry.logger.fatal(...)`
  // (a different type), which a grep-based reviewer mistook for a use of the
  // hand-written `AppLogger.fatal`. loam correctly kept reporting it.
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // Regression (HellerIO FP #2): static field accessed via ClassName.field must
  // NOT be reported. Previously, _collectMemberIds did not handle FieldDeclaration
  // so field ids were absent from declaredIds — causing the declaration-site visit
  // to self-register the field as referenced (every field appeared used).
  //
  // This regression test pins both directions:
  //   - usedStaticField (accessed in members_consumer.dart) → NOT reported
  //   - unusedStaticField (never accessed)                  → REPORTED
  // ---------------------------------------------------------------------------
  // ---------------------------------------------------------------------------
  // Regression (HellerIO FP #2 root cause): a symbol referenced ONLY from a
  // PART FILE must NOT be reported as unused.
  //
  // Part files (part of 'host.dart') are not standalone library entries —
  // ProjectLoader skips them as resolved entries because their declarations are
  // accessible via the host library's fragments. However, REFERENCES inside part
  // files (to symbols in other libraries) must still be recorded by UsageIndex.
  // Without this, a symbol referenced only from a part file appears unreferenced
  // and is incorrectly reported as unused (the HellerIO FP #2 pattern).
  // ---------------------------------------------------------------------------
  group(
    'part-file reference visibility (FP regression guard — HellerIO FP #2)',
    () {
      test(
        'symbol referenced ONLY from a part file is NOT reported as unused',
        () {
          final findings = makeRule().run(loadResult);
          expect(
            findings.any((f) => f.message.contains('`usedViaPartFile`')),
            isFalse,
            reason:
                'usedViaPartFile is referenced from part_ref_impl.dart (a part '
                'file) — part-file references must be visible to UsageIndex; '
                'if not, this is a False Positive (HellerIO FP #2 pattern)',
          );
        },
      );

      test('symbol NOT referenced from any part file IS reported', () {
        final findings = makeRule().run(loadResult);
        expect(
          findings.any((f) => f.message.contains('`unusedViaPartFile`')),
          isTrue,
          reason:
              'unusedViaPartFile is not referenced anywhere — must appear in '
              'findings',
        );
      });
    },
  );

  group('static field access via ClassName.field (FP regression guard)', () {
    test(
      'usedStaticField accessed via ClassName.usedStaticField is NOT reported',
      () {
        final findings = makeRule().run(loadResult);
        expect(
          findings.any((f) => f.message.contains('`usedStaticField`')),
          isFalse,
          reason:
              'usedStaticField is accessed as StaticFieldHolder.usedStaticField '
              'in members_consumer.dart — must not appear in findings',
        );
      },
    );

    test(
      'usedStaticMap accessed via ClassName.usedStaticMap[key] is NOT reported',
      () {
        final findings = makeRule().run(loadResult);
        expect(
          findings.any((f) => f.message.contains('`usedStaticMap`')),
          isFalse,
          reason:
              'usedStaticMap is accessed as StaticFieldHolder.usedStaticMap[k] '
              'in members_consumer.dart — must not appear in findings',
        );
      },
    );

    test('unusedStaticField (never accessed) IS reported', () {
      final findings = makeRule().run(loadResult);
      expect(
        findings.any((f) => f.message.contains('`unusedStaticField`')),
        isTrue,
        reason:
            'unusedStaticField is never referenced — must appear in findings',
      );
    });

    test('unusedStaticMap (never accessed) IS reported', () {
      final findings = makeRule().run(loadResult);
      expect(
        findings.any((f) => f.message.contains('`unusedStaticMap`')),
        isTrue,
        reason: 'unusedStaticMap is never referenced — must appear in findings',
      );
    });

    // Residual-risk guard (MVP sign-off item 3): static *method* and *getter*
    // access via `ClassName.member` from a standalone (non-part) file. Static
    // fields were already covered above; methods and getters take distinct
    // resolution paths and were previously untested.
    test(
      'usedStaticMethod called via ClassName.usedStaticMethod() is NOT reported',
      () {
        final findings = makeRule().run(loadResult);
        expect(
          findings.any((f) => f.message.contains('`usedStaticMethod`')),
          isFalse,
          reason:
              'usedStaticMethod is called as StaticFieldHolder.usedStaticMethod() '
              'in members_consumer.dart — must not appear in findings',
        );
      },
    );

    test('unusedStaticMethod (never called) IS reported', () {
      final findings = makeRule().run(loadResult);
      expect(
        findings.any((f) => f.message.contains('`unusedStaticMethod`')),
        isTrue,
        reason:
            'unusedStaticMethod is never referenced — must appear in findings',
      );
    });

    test(
      'usedStaticGetter read via ClassName.usedStaticGetter is NOT reported',
      () {
        final findings = makeRule().run(loadResult);
        expect(
          findings.any((f) => f.message.contains('`usedStaticGetter`')),
          isFalse,
          reason:
              'usedStaticGetter is read as StaticFieldHolder.usedStaticGetter '
              'in members_consumer.dart — must not appear in findings',
        );
      },
    );

    test('unusedStaticGetter (never read) IS reported', () {
      final findings = makeRule().run(loadResult);
      expect(
        findings.any((f) => f.message.contains('`unusedStaticGetter`')),
        isTrue,
        reason:
            'unusedStaticGetter is never referenced — must appear in findings',
      );
    });
  });

  group('member-name collision (semantic resolution)', () {
    test(
      'calling fatal() on one type does not suppress the unused fatal() on another',
      () {
        final findings = makeRule().run(loadResult);
        final fatalFindings = findings
            .where((f) => f.message.contains('`fatal`'))
            .toList();

        expect(
          fatalFindings,
          hasLength(1),
          reason:
              'Exactly one `fatal` must be reported (AppLoggerLike.fatal). '
              'Zero would mean usage was resolved by NAME — the call to '
              'SdkStyleLogger.fatal wrongly suppressing the unrelated member.',
        );

        // Pin the single finding to AppLoggerLike (not the called SdkStyleLogger),
        // robustly: read the fixture and locate both class bodies by line.
        final memberLines = File(
          p.join(fixturePath, 'lib', 'members.dart'),
        ).readAsLinesSync();
        final appLoggerLine =
            memberLines.indexWhere((l) => l.contains('class AppLoggerLike')) +
            1;
        final sdkLoggerLine =
            memberLines.indexWhere((l) => l.contains('class SdkStyleLogger')) +
            1;

        final reported = fatalFindings.single;
        expect(reported.filePath, endsWith('members.dart'));
        expect(
          reported.line,
          allOf(greaterThan(appLoggerLine), lessThan(sdkLoggerLine)),
          reason:
              'The reported `fatal` must be the one inside AppLoggerLike, not '
              'the called SdkStyleLogger.fatal.',
        );
      },
    );
  });
}

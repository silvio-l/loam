@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/rules/public_api_collector.dart';
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
  late List<PublicApiCandidate> candidates;
  const collector = PublicApiCollector();

  setUpAll(() async {
    final loader = ProjectLoader();
    loadResult = await loader.load(fixturePath);
    expect(loadResult.errors, isEmpty, reason: 'Fixture must load cleanly');
    candidates = collector.collect(loadResult, fixturePath);
  });

  // ---------------------------------------------------------------------------
  // Private class is never a candidate
  // ---------------------------------------------------------------------------
  test('_PrivateClass is never a candidate', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names.contains('_PrivateClass'),
      isFalse,
      reason: 'Private (underscore) symbols must never be candidates',
    );
  });

  // ---------------------------------------------------------------------------
  // Public classes under lib/ are candidates
  // ---------------------------------------------------------------------------
  test('public lib/ classes are candidates', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names,
      containsAll(['UsedClass', 'UnusedClass', 'AnotherUnusedClass']),
    );
  });

  // ---------------------------------------------------------------------------
  // Entrypoint (main) is never a candidate
  // ---------------------------------------------------------------------------
  test('main function is never a candidate', () {
    final mainCandidates = candidates.where((c) => c.name == 'main').toList();
    expect(
      mainCandidates,
      isEmpty,
      reason: 'main must be excluded as an entrypoint',
    );
  });

  // ---------------------------------------------------------------------------
  // Symbols from non-lib files (bin/test/tool) are not candidates
  // ---------------------------------------------------------------------------
  test('non-lib (bin/test/tool) files produce no candidates', () {
    final nonLibCandidates = candidates.where((c) {
      final path = c.relativePath;
      return path.startsWith('bin/') ||
          path.startsWith('test/') ||
          path.startsWith('tool/');
    }).toList();
    expect(
      nonLibCandidates,
      isEmpty,
      reason: 'Candidates must only come from lib/',
    );
  });

  // ---------------------------------------------------------------------------
  // All candidates have a non-empty name
  // ---------------------------------------------------------------------------
  test('all candidates have non-empty names', () {
    for (final c in candidates) {
      expect(c.name, isNotEmpty, reason: 'Candidate name must not be empty');
    }
  });

  // ---------------------------------------------------------------------------
  // All candidates have a non-empty POSIX relative path starting with lib/
  // ---------------------------------------------------------------------------
  test('all candidates have a POSIX lib/-relative path', () {
    for (final c in candidates) {
      expect(
        c.relativePath,
        startsWith('lib/'),
        reason: '${c.name} path should start with lib/',
      );
      expect(
        c.relativePath.contains(r'\'),
        isFalse,
        reason: 'Path must use forward slashes (POSIX)',
      );
    }
  });

  // ---------------------------------------------------------------------------
  // All candidates have a positive line number
  // ---------------------------------------------------------------------------
  test('all candidates have line > 0', () {
    for (final c in candidates) {
      expect(c.line, greaterThan(0), reason: '${c.name} must have line > 0');
    }
  });

  // ---------------------------------------------------------------------------
  // Kind label is set correctly for classes
  // ---------------------------------------------------------------------------
  test('kind label is "class" for class declarations', () {
    final usedClass = candidates.firstWhere(
      (c) => c.name == 'UsedClass',
      orElse: () => throw StateError('UsedClass not found'),
    );
    expect(usedClass.kind, 'class');
  });

  // ---------------------------------------------------------------------------
  // Collector handles empty ProjectLoadResult without crash
  // ---------------------------------------------------------------------------
  test('collect handles empty ProjectLoadResult without crash', () {
    const emptyResult = ProjectLoadResult(resolved: [], errors: []);
    final result = collector.collect(emptyResult, fixturePath);
    expect(result, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // Collector does not crash when errors list is non-empty
  // (it simply skips error files and processes the resolved ones)
  // ---------------------------------------------------------------------------
  test('collect handles non-empty errors list without crash', () {
    final resultWithErrors = ProjectLoadResult(
      resolved: loadResult.resolved,
      errors: const [
        LoadFileError(path: '/fake/broken.dart', reason: 'broken'),
      ],
    );
    final result = collector.collect(resultWithErrors, fixturePath);
    expect(result, isNotEmpty);
  });

  // ---------------------------------------------------------------------------
  // Issue 02 — All top-level declaration kinds are collected
  // ---------------------------------------------------------------------------

  test('top-level functions are candidates', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names,
      containsAll(['usedFunction', 'unusedFunction']),
      reason: 'Both used and unused top-level functions must be candidates',
    );
  });

  test('kind label is "function" for top-level function declarations', () {
    final fn = candidates.firstWhere(
      (c) => c.name == 'unusedFunction',
      orElse: () => throw StateError('unusedFunction not found'),
    );
    expect(fn.kind, 'function');
  });

  test('top-level getters are candidates', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names,
      containsAll(['usedGetter', 'unusedGetter']),
      reason: 'Both used and unused getters must be candidates',
    );
  });

  test('kind label is "getter" for explicit getter declarations', () {
    final g = candidates.firstWhere(
      (c) => c.name == 'unusedGetter',
      orElse: () => throw StateError('unusedGetter not found'),
    );
    expect(g.kind, 'getter');
  });

  test('top-level setters are candidates', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names,
      containsAll(['usedSetter', 'unusedSetter']),
      reason: 'Both used and unused setters must be candidates',
    );
  });

  test('kind label is "setter" for explicit setter declarations', () {
    final s = candidates.firstWhere(
      (c) => c.name == 'unusedSetter',
      orElse: () => throw StateError('unusedSetter not found'),
    );
    expect(s.kind, 'setter');
  });

  test('enums are candidates', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names,
      containsAll(['UsedEnum', 'UnusedEnum']),
      reason: 'Both used and unused enums must be candidates',
    );
  });

  test('kind label is "enum" for enum declarations', () {
    final e = candidates.firstWhere(
      (c) => c.name == 'UnusedEnum',
      orElse: () => throw StateError('UnusedEnum not found'),
    );
    expect(e.kind, 'enum');
  });

  test('extensions are candidates', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names,
      containsAll(['UsedExtension', 'UnusedExtension']),
      reason: 'Both used and unused extensions must be candidates',
    );
  });

  test('kind label is "extension" for extension declarations', () {
    final ext = candidates.firstWhere(
      (c) => c.name == 'UnusedExtension',
      orElse: () => throw StateError('UnusedExtension not found'),
    );
    expect(ext.kind, 'extension');
  });

  test('mixins are candidates', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names,
      containsAll(['UsedMixin', 'UnusedMixin']),
      reason: 'Both used and unused mixins must be candidates',
    );
  });

  test('kind label is "mixin" for mixin declarations', () {
    final m = candidates.firstWhere(
      (c) => c.name == 'UnusedMixin',
      orElse: () => throw StateError('UnusedMixin not found'),
    );
    expect(m.kind, 'mixin');
  });

  test('typedefs are candidates', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names,
      containsAll(['UsedTypedef', 'UnusedTypedef']),
      reason: 'Both used and unused typedefs must be candidates',
    );
  });

  test('kind label is "typedef" for typedef declarations', () {
    final t = candidates.firstWhere(
      (c) => c.name == 'UnusedTypedef',
      orElse: () => throw StateError('UnusedTypedef not found'),
    );
    expect(t.kind, 'typedef');
  });

  test('top-level variables are candidates', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names,
      containsAll(['usedVariable', 'unusedVariable']),
      reason: 'Both used and unused top-level variables must be candidates',
    );
  });

  test('kind label is "variable" for top-level variable declarations', () {
    final v = candidates.firstWhere(
      (c) => c.name == 'unusedVariable',
      orElse: () => throw StateError('unusedVariable not found'),
    );
    expect(v.kind, 'variable');
  });

  // ---------------------------------------------------------------------------
  // Issue 02 — Part-file declarations are collected (no duplicate, path correct)
  // ---------------------------------------------------------------------------

  test(
    'part-file declarations are candidates (UsedPartClass, UnusedPartClass)',
    () {
      final names = candidates.map((c) => c.name).toSet();
      expect(
        names,
        containsAll(['UsedPartClass', 'UnusedPartClass']),
        reason: 'Declarations in part files must be collected as candidates',
      );
    },
  );

  test(
    'part-file candidates carry the part file path, not the library path',
    () {
      final partCandidate = candidates.firstWhere(
        (c) => c.name == 'UnusedPartClass',
        orElse: () => throw StateError('UnusedPartClass not found'),
      );
      expect(
        partCandidate.relativePath,
        'lib/all_kinds_part.dart',
        reason:
            'Part-file declaration must show the part file path, not the '
            'library file path',
      );
    },
  );

  test('no duplicate candidates for part-file declarations', () {
    final partClassCandidates = candidates
        .where((c) => c.name == 'UnusedPartClass')
        .toList();
    expect(
      partClassCandidates.length,
      1,
      reason:
          'Part-file declarations must appear exactly once (no dedup via '
          'element identity)',
    );
  });

  test(
    'no duplicate candidates for library-file declarations (part present)',
    () {
      // With a part file present, library-file declarations must not be doubled.
      final usedEnumCandidates = candidates
          .where((c) => c.name == 'UsedEnum')
          .toList();
      expect(
        usedEnumCandidates.length,
        1,
        reason: 'Library-file declarations must appear exactly once',
      );
    },
  );

  test('all candidates have unique element ids (no structural duplicates)', () {
    final ids = candidates.map((c) => c.element.id).toList();
    final uniqueIds = ids.toSet();
    expect(
      ids.length,
      uniqueIds.length,
      reason:
          'Each candidate must have a unique element id — no structural '
          'duplicates across fragments',
    );
  });

  // ---------------------------------------------------------------------------
  // Issue 03 — AC1: Generated-file exclusion
  // Symbols declared in *.g.dart files are NOT candidates.
  // ---------------------------------------------------------------------------

  test('AC1-gen: GeneratedClass (from *.g.dart) is NOT a candidate', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names.contains('GeneratedClass'),
      isFalse,
      reason: 'Symbols declared in *.g.dart files must never be candidates',
    );
  });

  // ---------------------------------------------------------------------------
  // Issue 03 — AC2: Re-exported symbol exclusion
  // Symbols re-exported via `export` directives are NOT candidates.
  // ---------------------------------------------------------------------------

  test(
    'AC2-reexport: ReExportedClass (re-exported via barrel) is NOT a candidate',
    () {
      final names = candidates.map((c) => c.name).toSet();
      expect(
        names.contains('ReExportedClass'),
        isFalse,
        reason:
            'Symbols re-exported via `export` directives must never be candidates',
      );
    },
  );

  test(
    'AC2-reexport: top-level getter re-exported via barrel is NOT a candidate',
    () {
      final names = candidates.map((c) => c.name).toSet();
      expect(
        names.contains('reExportedGetter'),
        isFalse,
        reason:
            'Top-level getters re-exported via `export` directives must never be candidates',
      );
    },
  );

  test(
    'AC2-reexport: top-level setter re-exported via barrel is NOT a candidate',
    () {
      final names = candidates.map((c) => c.name).toSet();
      expect(
        names.contains('reExportedSetter'),
        isFalse,
        reason:
            'Top-level setters re-exported via `export` directives must never be candidates',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // Issue 03 — AC3: Annotation exclusion
  // @visibleForTesting and @pragma annotated symbols are NOT candidates.
  // ---------------------------------------------------------------------------

  test('AC3-annotation: @visibleForTesting class is NOT a candidate', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names.contains('VisibleForTestingClass'),
      isFalse,
      reason:
          'Symbols annotated with @visibleForTesting must never be candidates',
    );
  });

  test('AC3-annotation: @pragma class is NOT a candidate', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names.contains('PragmaAnnotatedClass'),
      isFalse,
      reason: 'Symbols annotated with @pragma must never be candidates',
    );
  });

  // ---------------------------------------------------------------------------
  // Issue 02 — AC1/AC2: @internal and @visibleForOverriding exclusion
  // ---------------------------------------------------------------------------

  test('AC1-annotation: @internal class is NOT a candidate', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names.contains('InternalAnnotatedClass'),
      isFalse,
      reason: 'Symbols annotated with @internal must never be candidates',
    );
  });

  test('AC2-annotation: @visibleForOverriding class is NOT a candidate', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names.contains('VisibleForOverridingClass'),
      isFalse,
      reason:
          'Symbols annotated with @visibleForOverriding must never be candidates',
    );
  });

  // ---------------------------------------------------------------------------
  // Issue 04 — Slice B: Member candidates are collected
  // ---------------------------------------------------------------------------

  test('SliceB-AC1: unused public method is a candidate', () {
    final memberCandidates = candidates
        .where((c) => c.name == 'unusedMethod')
        .toList();
    expect(
      memberCandidates,
      isNotEmpty,
      reason: 'unusedMethod (public method on MemberHost) must be a candidate',
    );
    final c = memberCandidates.first;
    expect(c.kind, 'method');
    expect(c.semanticAnchor, 'MemberHost.unusedMethod');
  });

  test('SliceB-AC1: unused public field is a candidate', () {
    final fieldCandidates = candidates
        .where((c) => c.name == 'unusedField')
        .toList();
    expect(
      fieldCandidates,
      isNotEmpty,
      reason: 'unusedField (public field on MemberHost) must be a candidate',
    );
    final c = fieldCandidates.first;
    expect(c.kind, 'field');
    expect(c.semanticAnchor, 'MemberHost.unusedField');
  });

  test('SliceB-AC1: unused public member getter is a candidate', () {
    final getterCandidates = candidates
        .where((c) => c.name == 'unusedMemberGetter')
        .toList();
    expect(
      getterCandidates,
      isNotEmpty,
      reason:
          'unusedMemberGetter (public getter on MemberHost) must be a candidate',
    );
    final c = getterCandidates.first;
    expect(c.kind, 'getter');
    expect(c.semanticAnchor, 'MemberHost.unusedMemberGetter');
  });

  test('SliceB-AC1: unused public member setter is a candidate', () {
    final setterCandidates = candidates
        .where((c) => c.name == 'unusedMemberSetter')
        .toList();
    expect(
      setterCandidates,
      isNotEmpty,
      reason:
          'unusedMemberSetter (public setter on MemberHost) must be a candidate',
    );
    final c = setterCandidates.first;
    expect(c.kind, 'setter');
    expect(c.semanticAnchor, 'MemberHost.unusedMemberSetter');
  });

  test('SliceB-AC1: unused public enum method is a candidate', () {
    final enumMethodCandidates = candidates
        .where((c) => c.name == 'unusedEnumMethod')
        .toList();
    expect(
      enumMethodCandidates,
      isNotEmpty,
      reason:
          'unusedEnumMethod (public method on MemberEnum) must be a candidate',
    );
    final c = enumMethodCandidates.first;
    expect(c.kind, 'method');
    expect(c.semanticAnchor, 'MemberEnum.unusedEnumMethod');
  });

  test(
    'SliceB-AC2: used public method is a candidate (referenced elsewhere)',
    () {
      // usedMethod IS a candidate but should be referenced → not reported as unused.
      final usedMethodCandidates = candidates
          .where((c) => c.name == 'usedMethod')
          .toList();
      // Candidate must exist; referenced check happens in the rule, not here.
      expect(
        usedMethodCandidates,
        isNotEmpty,
        reason: 'usedMethod must be collected as a candidate',
      );
    },
  );

  test('SliceB-AC3: @override method is NOT a candidate', () {
    // MemberHost.interfaceMethod is @override — must not appear in candidates.
    final overrideCandidates = candidates
        .where((c) => c.name == 'interfaceMethod')
        .toList();
    expect(
      overrideCandidates,
      isEmpty,
      reason: 'interfaceMethod carries @override — must never be a candidate',
    );
  });

  test('SliceB-AC3: @override getter is NOT a candidate', () {
    // MemberHost.interfaceGetter is @override — must not appear in candidates.
    final overrideCandidates = candidates
        .where((c) => c.name == 'interfaceGetter')
        .toList();
    expect(
      overrideCandidates,
      isEmpty,
      reason: 'interfaceGetter carries @override — must never be a candidate',
    );
  });

  test('SliceB-AC3: Object.toString() override is NOT a candidate', () {
    // HasOverrideMethod.toString is @override — must not appear in candidates.
    final overrideCandidates = candidates
        .where((c) => c.name == 'toString')
        .toList();
    expect(
      overrideCandidates,
      isEmpty,
      reason: 'toString() with @override must never be a candidate',
    );
  });

  test('SliceB-AC4: enum values field (synthetic) is NOT a candidate', () {
    // Enum.values and Enum.index are synthetic — must never be candidates.
    final syntheticCandidates = candidates
        .where((c) => c.name == 'values' || c.name == 'index')
        .toList();
    expect(
      syntheticCandidates,
      isEmpty,
      reason: 'Synthetic enum fields (values/index) must never be candidates',
    );
  });

  test('SliceB-AC4: enum constants are NOT candidates', () {
    // Enum constant fields (alpha, beta) must not be member candidates.
    final enumConstCandidates = candidates
        .where((c) => c.name == 'alpha' || c.name == 'beta')
        .toList();
    expect(
      enumConstCandidates,
      isEmpty,
      reason: 'Enum constant fields must never be member candidates',
    );
  });

  test('SliceB-AC5: member candidates have qualified semanticAnchor', () {
    final methodCandidate = candidates.firstWhere(
      (c) => c.name == 'unusedMethod',
      orElse: () => throw StateError('unusedMethod not found'),
    );
    expect(
      methodCandidate.semanticAnchor,
      contains('.'),
      reason: 'Member semanticAnchor must be qualified (ClassName.memberName)',
    );
    expect(methodCandidate.semanticAnchor, 'MemberHost.unusedMethod');
  });

  test('SliceB-AC5: top-level candidates have unqualified semanticAnchor', () {
    // Top-level symbols must still use just their name as anchor.
    final topLevelCandidate = candidates.firstWhere(
      (c) => c.name == 'unusedFunction',
      orElse: () => throw StateError('unusedFunction not found'),
    );
    expect(
      topLevelCandidate.semanticAnchor,
      'unusedFunction',
      reason: 'Top-level semanticAnchor must remain unqualified',
    );
  });

  test('SliceB: members of re-exported classes are NOT candidates', () {
    // ReExportedClass is re-exported — its members must not be candidates.
    // 'name' getter from ReExportedClass would appear in re_exported_origin.dart.
    final reExportedMemberCandidates = candidates.where((c) {
      return c.semanticAnchor.startsWith('ReExportedClass.');
    }).toList();
    expect(
      reExportedMemberCandidates,
      isEmpty,
      reason: 'Members of re-exported classes must never be candidates',
    );
  });

  test('SliceB: members of @visibleForTesting class are NOT candidates', () {
    // VisibleForTestingClass members must be excluded transitively.
    final annotatedMemberCandidates = candidates.where((c) {
      return c.semanticAnchor.startsWith('VisibleForTestingClass.');
    }).toList();
    expect(
      annotatedMemberCandidates,
      isEmpty,
      reason: 'Members of @visibleForTesting classes must never be candidates',
    );
  });

  test('SliceB: abstract interface methods are NOT candidates', () {
    // MemberInterface.interfaceMethod and MemberInterface.interfaceGetter
    // are abstract — must never be candidates.
    final abstractCandidates = candidates.where((c) {
      return c.semanticAnchor.startsWith('MemberInterface.');
    }).toList();
    expect(
      abstractCandidates,
      isEmpty,
      reason: 'Abstract interface methods/getters must never be candidates',
    );
  });

  test('SliceB: all member candidates have line > 0', () {
    final memberCandidates = candidates.where((c) {
      return c.kind == 'method' ||
          c.kind == 'field' ||
          (c.kind == 'getter' && c.semanticAnchor.contains('.')) ||
          (c.kind == 'setter' && c.semanticAnchor.contains('.'));
    }).toList();
    for (final c in memberCandidates) {
      expect(
        c.line,
        greaterThan(0),
        reason: '${c.semanticAnchor} must have line > 0',
      );
    }
  });
}

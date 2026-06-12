@TestOn('vm')
library;

import 'dart:io';

import 'package:analyzer/dart/element/element.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/rules/codegen_input_classifier.dart';
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

  const classifier = CodegenInputClassifier();

  // ---------------------------------------------------------------------------
  // AC1: CodegenInputClassifier exists with { isCodegenInput, reason } interface
  // ---------------------------------------------------------------------------

  test(
    'AC1: CodegenInputClassification has isCodegenInput and reason fields',
    () {
      // Verify the public interface exists and is accessible.
      const result = CodegenInputClassification.none;
      expect(result.isCodegenInput, isFalse);
      expect(result.reason, 'none');
    },
  );

  test(
    'AC1: CodegenInputClassifier.classify() returns CodegenInputClassification',
    () {
      // Verify we can call classify() and get a structured result.
      // Use a non-InterfaceElement (library element) — must return none.
      for (final file in loadResult.resolved) {
        final lib = file.result.libraryElement;
        final result = classifier.classify(lib);
        expect(result, isA<CodegenInputClassification>());
        expect(
          result.isCodegenInput,
          isFalse,
          reason: 'LibraryElement is not a class — must return none',
        );
        break;
      }
    },
  );

  // ---------------------------------------------------------------------------
  // AC2: Drift Table subclass is classified as code-gen input (base-type path)
  // ---------------------------------------------------------------------------

  test('AC2: DriftTable (extends Table) is classified as code-gen input', () {
    final driftTableClass = _findClass(loadResult, 'DriftTable');
    expect(
      driftTableClass,
      isNotNull,
      reason: 'DriftTable must exist in the fixture',
    );

    final result = classifier.classify(driftTableClass!);
    expect(
      result.isCodegenInput,
      isTrue,
      reason: 'DriftTable extends Table — must be a code-gen input',
    );
    expect(
      result.reason,
      startsWith('base_type:'),
      reason: 'Reason must identify the base-type registry path',
    );
    expect(result.reason, contains('Table'));
  });

  test(
    'AC2: DriftDataClass (extends DataClass) is classified as code-gen input',
    () {
      final driftDataClass = _findClass(loadResult, 'DriftDataClass');
      expect(
        driftDataClass,
        isNotNull,
        reason: 'DriftDataClass must exist in the fixture',
      );

      final result = classifier.classify(driftDataClass!);
      expect(
        result.isCodegenInput,
        isTrue,
        reason: 'DriftDataClass extends DataClass — must be a code-gen input',
      );
      expect(
        result.reason,
        startsWith('base_type:'),
        reason: 'Reason must identify the base-type registry path',
      );
      expect(result.reason, contains('DataClass'));
    },
  );

  test('AC2: DriftView (extends View) is classified as code-gen input', () {
    final driftViewClass = _findClass(loadResult, 'DriftView');
    expect(
      driftViewClass,
      isNotNull,
      reason: 'DriftView must exist in the fixture',
    );

    final result = classifier.classify(driftViewClass!);
    expect(
      result.isCodegenInput,
      isTrue,
      reason: 'DriftView extends View — must be a code-gen input',
    );
    expect(
      result.reason,
      startsWith('base_type:'),
      reason: 'Reason must identify the base-type registry path',
    );
    expect(result.reason, contains('View'));
  });

  // ---------------------------------------------------------------------------
  // AC3: Normal class without markers → not a code-gen input (reason: none)
  // ---------------------------------------------------------------------------

  test(
    'AC3: PlainClass (no markers, no generated part) → NOT code-gen input',
    () {
      final plainClass = _findClass(loadResult, 'PlainClass');
      expect(
        plainClass,
        isNotNull,
        reason: 'PlainClass must exist in the fixture',
      );

      final result = classifier.classify(plainClass!);
      expect(
        result.isCodegenInput,
        isFalse,
        reason:
            'PlainClass has no code-gen markers — must NOT be a code-gen input',
      );
      expect(
        result.reason,
        'none',
        reason: 'reason must be "none" for a plain class',
      );
    },
  );

  test(
    'AC3: PlainConsumer (no markers, no generated part) → NOT code-gen input',
    () {
      final plainConsumer = _findClass(loadResult, 'PlainConsumer');
      expect(
        plainConsumer,
        isNotNull,
        reason: 'PlainConsumer must exist in the fixture',
      );

      final result = classifier.classify(plainConsumer!);
      expect(
        result.isCodegenInput,
        isFalse,
        reason:
            'PlainConsumer has no code-gen markers — must NOT be a code-gen input',
      );
      expect(result.reason, 'none');
    },
  );

  // ---------------------------------------------------------------------------
  // AC3-extended: stub base types themselves (Table, DataClass, View) are in
  // the fixture but should NOT self-classify (they don't extend another
  // registered base type — only their subclasses do).
  // ---------------------------------------------------------------------------

  test('stub Table base class itself is NOT classified as code-gen input', () {
    final tableClass = _findClass(loadResult, 'Table');
    expect(
      tableClass,
      isNotNull,
      reason: 'Stub Table must exist in the fixture',
    );

    final result = classifier.classify(tableClass!);
    // The Table class itself does not extend anything in the registry.
    // It may or may not be flagged depending on fallback — but since it has
    // no part directive and no annotation, it should be none.
    expect(
      result.isCodegenInput,
      isFalse,
      reason: 'The abstract Table base class itself is not a code-gen input',
    );
  });

  // ---------------------------------------------------------------------------
  // Annotation registry: each known annotation → code-gen input, reason starts
  // with 'annotation:' and includes the annotation name.
  // Registry paths are checked BEFORE the heuristic fallback (order guarantee).
  // ---------------------------------------------------------------------------

  group('annotation registry', () {
    // Helper: verifies annotation path is taken and the reason contains [name].
    void expectAnnotationMatch(String className, String annotationName) {
      final cls = _findClass(loadResult, className);
      expect(cls, isNotNull, reason: '$className must exist in the fixture');

      final result = classifier.classify(cls!);
      expect(
        result.isCodegenInput,
        isTrue,
        reason:
            '$className carries @$annotationName → must be a code-gen input',
      );
      expect(
        result.reason,
        startsWith('annotation:'),
        reason: 'Registry path must produce an annotation: reason',
      );
      expect(
        result.reason,
        contains(annotationName),
        reason: 'reason must name the matched annotation ($annotationName)',
      );
    }

    test('@DriftDatabase → code-gen input', () {
      expectAnnotationMatch('AnnotatedDriftDatabase', 'DriftDatabase');
    });

    test('@DataClassName → code-gen input', () {
      expectAnnotationMatch('AnnotatedDataClassName', 'DataClassName');
    });

    test('@Riverpod() (class form) → code-gen input', () {
      expectAnnotationMatch('AnnotatedRiverpodClass', 'Riverpod');
    });

    test('@riverpod (constant form) → code-gen input', () {
      expectAnnotationMatch('AnnotatedRiverpodConst', 'riverpod');
    });

    test('@freezed → code-gen input', () {
      expectAnnotationMatch('AnnotatedFreezed', 'freezed');
    });

    test('@JsonSerializable → code-gen input', () {
      expectAnnotationMatch('AnnotatedJsonSerializable', 'JsonSerializable');
    });

    test(
      'annotation reason is NOT fallback:part_generated (registry path first)',
      () {
        // AnnotatedJsonSerializable has no part directive — if it were classified
        // via the fallback, the reason would be 'fallback:part_generated'.
        // Verifies that the annotation path runs BEFORE the fallback.
        final cls = _findClass(loadResult, 'AnnotatedJsonSerializable');
        expect(cls, isNotNull);
        final result = classifier.classify(cls!);
        expect(result.reason, isNot('fallback:part_generated'));
        expect(result.reason, startsWith('annotation:'));
      },
    );

    test('@injectable (constant form) → code-gen input', () {
      expectAnnotationMatch('AnnotatedInjectable', 'injectable');
    });

    test('@module (constant form) → code-gen input', () {
      expectAnnotationMatch('AnnotatedModule', 'module');
    });

    test('@RoutePage → code-gen input', () {
      expectAnnotationMatch('AnnotatedRoutePage', 'RoutePage');
    });

    test('@GenerateMocks → code-gen input', () {
      expectAnnotationMatch('AnnotatedGenerateMocks', 'GenerateMocks');
    });

    test('@Collection (Isar) → code-gen input', () {
      expectAnnotationMatch('AnnotatedCollection', 'Collection');
    });

    test('@Entity (ObjectBox/floor) → code-gen input', () {
      expectAnnotationMatch('AnnotatedEntity', 'Entity');
    });

    test('@HiveType (Hive) → code-gen input', () {
      expectAnnotationMatch('AnnotatedHiveType', 'HiveType');
    });

    test(
      'negative: class without annotation → NOT code-gen input (reason: none)',
      () {
        final cls = _findClass(loadResult, 'PlainClass');
        expect(cls, isNotNull);
        final result = classifier.classify(cls!);
        expect(result.isCodegenInput, isFalse);
        expect(result.reason, 'none');
      },
    );

    test(
      'order: class with BOTH annotation AND generated part → annotation reason '
      '(registry runs before fallback)',
      () {
        // RegistryAndPartClass carries @JsonSerializable AND lives in a library
        // with part 'registry_and_part.g.dart'. The annotation-registry path
        // must win — reason must start with 'annotation:', NOT 'fallback:'.
        final cls = _findClass(loadResult, 'RegistryAndPartClass');
        expect(
          cls,
          isNotNull,
          reason: 'RegistryAndPartClass must exist in the fixture',
        );

        final result = classifier.classify(cls!);
        expect(
          result.isCodegenInput,
          isTrue,
          reason:
              'RegistryAndPartClass carries @JsonSerializable — must be code-gen input',
        );
        expect(
          result.reason,
          startsWith('annotation:'),
          reason:
              'Registry path must take priority over structural fallback; '
              'got reason: ${result.reason}',
        );
        expect(
          result.reason,
          isNot('fallback:part_generated'),
          reason: 'Fallback must NOT fire when a registry path already matched',
        );
      },
    );
  });

  // ---------------------------------------------------------------------------
  // Narrowed fallback: a class in a library with part '*.g.dart' is a code-gen
  // input ONLY when it itself binds a generated `_$`-counterpart.
  // ---------------------------------------------------------------------------

  test(
    'fallback: PartHeuristicNotifier (part *.g.dart + extends _\$…) → code-gen input',
    () {
      final partClass = _findClass(loadResult, 'PartHeuristicNotifier');
      expect(
        partClass,
        isNotNull,
        reason: 'PartHeuristicNotifier must exist in the fixture',
      );

      final result = classifier.classify(partClass!);
      expect(
        result.isCodegenInput,
        isTrue,
        reason:
            'PartHeuristicNotifier binds its generated counterpart '
            '(extends _\$PartHeuristicNotifier) in a part-bearing library — '
            'must be classified via the narrowed fallback heuristic',
      );
      expect(result.reason, 'fallback:part_generated');
    },
  );

  // ---------------------------------------------------------------------------
  // New generated suffixes: *.gr.dart, *.config.dart, *.mocks.dart, *.pb.dart
  // ---------------------------------------------------------------------------

  test('suffix *.gr.dart: GrSuffixRouter (part *.gr.dart + extends _\$…) → '
      'code-gen input', () {
    final cls = _findClass(loadResult, 'GrSuffixRouter');
    expect(cls, isNotNull, reason: 'GrSuffixRouter must exist in the fixture');
    final result = classifier.classify(cls!);
    expect(
      result.isCodegenInput,
      isTrue,
      reason:
          'GrSuffixRouter binds _\$… in a library with part *.gr.dart — '
          'must be classified via the narrowed fallback',
    );
    expect(result.reason, 'fallback:part_generated');
  });

  test(
    'suffix *.config.dart: ConfigSuffixModule (part *.config.dart + extends _\$…) → '
    'code-gen input',
    () {
      final cls = _findClass(loadResult, 'ConfigSuffixModule');
      expect(
        cls,
        isNotNull,
        reason: 'ConfigSuffixModule must exist in the fixture',
      );
      final result = classifier.classify(cls!);
      expect(
        result.isCodegenInput,
        isTrue,
        reason:
            'ConfigSuffixModule binds _\$… in a library with part *.config.dart — '
            'must be classified via the narrowed fallback',
      );
      expect(result.reason, 'fallback:part_generated');
    },
  );

  test(
    'suffix *.mocks.dart: MocksSuffixLib (part *.mocks.dart + extends _\$…) → '
    'code-gen input',
    () {
      final cls = _findClass(loadResult, 'MocksSuffixLib');
      expect(
        cls,
        isNotNull,
        reason: 'MocksSuffixLib must exist in the fixture',
      );
      final result = classifier.classify(cls!);
      expect(
        result.isCodegenInput,
        isTrue,
        reason:
            'MocksSuffixLib binds _\$… in a library with part *.mocks.dart — '
            'must be classified via the narrowed fallback',
      );
      expect(result.reason, 'fallback:part_generated');
    },
  );

  test('suffix *.pb.dart: PbSuffixMessage (part *.pb.dart + extends _\$…) → '
      'code-gen input', () {
    final cls = _findClass(loadResult, 'PbSuffixMessage');
    expect(cls, isNotNull, reason: 'PbSuffixMessage must exist in the fixture');
    final result = classifier.classify(cls!);
    expect(
      result.isCodegenInput,
      isTrue,
      reason:
          'PbSuffixMessage binds _\$… in a library with part *.pb.dart — '
          'must be classified via the narrowed fallback',
    );
    expect(result.reason, 'fallback:part_generated');
  });

  test(
    'narrowed fallback (FN-protection): PlainColocatedClass (part *.g.dart but '
    'NO _\$ binding) → NOT code-gen input',
    () {
      final plain = _findClass(loadResult, 'PlainColocatedClass');
      expect(
        plain,
        isNotNull,
        reason: 'PlainColocatedClass must exist in the fixture',
      );

      final result = classifier.classify(plain!);
      expect(
        result.isCodegenInput,
        isFalse,
        reason:
            'PlainColocatedClass is hand-written and binds no generated '
            '_\$-counterpart, even though its library declares part *.g.dart — '
            'it must NOT be suppressed (mirrors Hellerio PremiumEntitlement)',
      );
      expect(result.reason, 'none');
    },
  );
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Finds a class element by unqualified name across all resolved files.
ClassElement? _findClass(ProjectLoadResult result, String name) {
  for (final file in result.resolved) {
    final library = file.result.libraryElement;
    for (final cls in library.classes) {
      if (cls.name == name) return cls;
    }
  }
  return null;
}

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
  // Fallback: class in a library with part '*.g.dart' is classified via heuristic
  // ---------------------------------------------------------------------------

  test(
    'fallback: PartHeuristicClass (library has part *.g.dart) → code-gen input',
    () {
      final partClass = _findClass(loadResult, 'PartHeuristicClass');
      expect(
        partClass,
        isNotNull,
        reason: 'PartHeuristicClass must exist in the fixture',
      );

      final result = classifier.classify(partClass!);
      expect(
        result.isCodegenInput,
        isTrue,
        reason:
            'PartHeuristicClass lives in a library with part *.g.dart — '
            'must be classified via fallback heuristic',
      );
      expect(result.reason, 'fallback:part_generated');
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

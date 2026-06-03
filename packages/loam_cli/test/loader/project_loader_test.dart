@TestOn('vm')
library;

import 'dart:io';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Resolve the fixture path relative to this test file's location.
  // `dart test` runs with CWD = packages/loam_cli/.
  final fixturePath = p.normalize(
    p.join(Directory.current.path, 'test', 'fixtures', 'cross_file_fixture'),
  );

  late ProjectLoadResult loadResult;

  setUpAll(() async {
    final loader = ProjectLoader();
    loadResult = await loader.load(fixturePath);
  });

  // ---------------------------------------------------------------------------
  // AC1: ProjectLoader returns a ProjectLoadResult without throwing.
  // ---------------------------------------------------------------------------
  test('AC1: load() returns ProjectLoadResult without throwing', () {
    expect(loadResult, isA<ProjectLoadResult>());
  });

  // ---------------------------------------------------------------------------
  // AC2: Every lib/ file has a resolved entry with non-empty element model
  //      and libraryElement is reachable.
  // ---------------------------------------------------------------------------
  group('AC2: lib/ files have ResolvedUnitResult with libraryElement', () {
    late List<LoadedFile> libFiles;

    setUp(() {
      libFiles = loadResult.resolved.where((f) => f.isUnderLib).toList();
    });

    test('both lib/ files are present', () {
      final libPaths = libFiles.map((f) => p.basename(f.path)).toSet();
      expect(libPaths, containsAll(['greeter.dart', 'app.dart']));
    });

    test('each lib/ entry carries a non-empty libraryElement', () {
      for (final file in libFiles) {
        expect(
          file.result.libraryElement,
          isNotNull,
          reason: '${p.basename(file.path)} must have a libraryElement',
        );
        // The library element must expose at least one fragment (itself).
        expect(file.result.libraryElement.fragments, isNotEmpty);
      }
    });
  });

  // ---------------------------------------------------------------------------
  // AC3: Cross-file reference in app.dart resolves to the element declared in
  //      greeter.dart (hard prerequisite for the Tracer Rule).
  // ---------------------------------------------------------------------------
  test(
    'AC3: Greeter reference in app.dart resolves to element in greeter.dart',
    () {
      // Find app.dart resolved entry.
      final appEntry = loadResult.resolved.firstWhere(
        (f) => p.basename(f.path) == 'app.dart',
        orElse: () =>
            throw StateError('app.dart not found in resolved entries'),
      );

      // Walk the AST to find all SimpleIdentifiers named "Greeter".
      final unit = appEntry.result.unit;
      final greeterRefs = <SimpleIdentifier>[];
      unit.accept(_CollectIdentifiers('Greeter', greeterRefs));

      expect(
        greeterRefs,
        isNotEmpty,
        reason: 'No "Greeter" identifiers in app.dart',
      );

      // At least one reference must resolve to an element whose source file
      // is greeter.dart.
      //
      // In analyzer v13, Element no longer exposes .source directly. The source
      // lives on Fragment: element.firstFragment.libraryFragment?.source.fullName
      final resolvedToGreeterFile = greeterRefs.any((id) {
        // In analyzer v13 SimpleIdentifier.element replaces staticElement.
        final element = id.element;
        if (element == null) return false;
        final sourceFullName =
            element.firstFragment.libraryFragment?.source.fullName ?? '';
        return sourceFullName.endsWith('greeter.dart');
      });

      expect(
        resolvedToGreeterFile,
        isTrue,
        reason: 'At least one "Greeter" reference must resolve to greeter.dart',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // AC4: Every resolved entry has a normalised absolute path and correct
  //      isUnderLib flag.
  // ---------------------------------------------------------------------------
  test(
    'AC4: entries have normalised absolute paths and correct isUnderLib',
    () {
      for (final file in loadResult.resolved) {
        expect(
          p.isAbsolute(file.path),
          isTrue,
          reason: '${file.path} should be absolute',
        );
        expect(
          file.path,
          equals(p.normalize(file.path)),
          reason: '${file.path} should be normalised',
        );

        final relToRoot = p.relative(file.path, from: fixturePath);
        final expectedUnderLib = relToRoot.startsWith('lib${p.separator}');
        expect(
          file.isUnderLib,
          equals(expectedUnderLib),
          reason: '${file.path} isUnderLib mismatch',
        );
      }
    },
  );

  // ---------------------------------------------------------------------------
  // AC5: bin/, test/, tool/ files are loaded (not filtered), distinguished by
  //      isUnderLib = false.
  // ---------------------------------------------------------------------------
  test('AC5: bin/, test/, tool/ files are loaded with isUnderLib = false', () {
    final nonLibFiles = loadResult.resolved
        .where((f) => !f.isUnderLib)
        .toList();
    final basenames = nonLibFiles.map((f) => p.basename(f.path)).toSet();

    // Fixture has: bin/main.dart, test/greeter_test.dart, tool/generate.dart
    expect(
      basenames,
      containsAll(['main.dart', 'greeter_test.dart', 'generate.dart']),
    );

    for (final file in nonLibFiles) {
      expect(file.isUnderLib, isFalse);
    }
  });

  // ---------------------------------------------------------------------------
  // AC6 (structural): ProjectLoader source must not reference Finding/Rule/
  //     Reporter or CLI types. Verified by a source-text grep.
  // ---------------------------------------------------------------------------
  test(
    'AC6: loader source has no references to Finding/Rule/Reporter/CLI types',
    () {
      final loaderFile = File(
        p.join(
          Directory.current.path,
          'lib',
          'src',
          'loader',
          'project_loader.dart',
        ),
      );
      expect(loaderFile.existsSync(), isTrue);
      final source = loaderFile.readAsStringSync();
      for (final forbidden in [
        'Finding',
        'Reporter',
        'LoamCommand',
        'globalResults',
      ]) {
        expect(
          source.contains(forbidden),
          isFalse,
          reason: 'project_loader.dart must not reference $forbidden',
        );
      }
      // Also ensure no *.g.dart filtering is present.
      expect(
        source.contains('.g.dart'),
        isFalse,
        reason: 'project_loader.dart must not filter generated files',
      );
    },
  );
}

// ---------------------------------------------------------------------------
// AST visitor helper — collects all SimpleIdentifiers matching [name].
// ---------------------------------------------------------------------------
class _CollectIdentifiers extends RecursiveAstVisitor<void> {
  _CollectIdentifiers(this.name, this.collected);

  final String name;
  final List<SimpleIdentifier> collected;

  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    if (node.name == node.name && node.name == name) collected.add(node);
    super.visitSimpleIdentifier(node);
  }
}

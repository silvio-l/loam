@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Resolve the fixture path relative to packages/loam_cli/ (dart test CWD).
  final fixturePath = p.normalize(
    p.join(Directory.current.path, 'test', 'fixtures', 'part_fixture'),
  );

  late ProjectLoadResult result;

  setUpAll(() async {
    final loader = ProjectLoader();
    result = await loader.load(fixturePath);
  });

  // ---------------------------------------------------------------------------
  // AC1: No duplicate or contradictory element-model entry for a declaration
  //      that lives across library + part files.
  // ---------------------------------------------------------------------------
  test('AC1: no duplicate resolved entries for the same declaration across '
      'library and part files', () {
    // Collect all resolved file paths.
    final paths = result.resolved.map((f) => f.path).toList();

    // No path may appear twice.
    final uniquePaths = paths.toSet();
    expect(
      paths.length,
      equals(uniquePaths.length),
      reason: 'Duplicate resolved entries found: $paths',
    );
  });

  // ---------------------------------------------------------------------------
  // AC2: The part file is NOT listed as a standalone resolved library entry.
  //      It must NOT appear in resolved, only the library file should.
  // ---------------------------------------------------------------------------
  test('AC2: the part file (my_library_part.dart) does not appear as a '
      'standalone resolved library entry', () {
    final partEntry = result.resolved.where(
      (f) => p.basename(f.path) == 'my_library_part.dart',
    );
    expect(
      partEntry,
      isEmpty,
      reason:
          'my_library_part.dart must not be in resolved as a standalone library',
    );
  });

  // ---------------------------------------------------------------------------
  // AC2b: The part file must also NOT appear in errors (it is a valid part).
  // ---------------------------------------------------------------------------
  test('AC2b: the part file (my_library_part.dart) does not appear in errors '
      '(it is a legitimate part, not a broken file)', () {
    final partError = result.errors.where(
      (e) => p.basename(e.path) == 'my_library_part.dart',
    );
    expect(
      partError,
      isEmpty,
      reason:
          'my_library_part.dart must not be in errors — it is a valid part file',
    );
  });

  // ---------------------------------------------------------------------------
  // AC3: Declarations spread across library + part are reachable via the
  //      library's resolved element model.
  //      MyLibrary is declared in my_library.dart,
  //      MyLibraryPart is declared in my_library_part.dart.
  //      Both must be reachable via the libraryElement of the library entry.
  // ---------------------------------------------------------------------------
  test('AC3: declarations spread across library and part are reachable via '
      'the library entry\'s libraryElement', () {
    final libraryEntry = result.resolved.firstWhere(
      (f) => p.basename(f.path) == 'my_library.dart',
      orElse: () => throw StateError(
        'my_library.dart not found in resolved — resolved paths: '
        '${result.resolved.map((f) => f.path).toList()}',
      ),
    );

    final libraryElement = libraryEntry.result.libraryElement;
    expect(libraryElement, isNotNull);

    // Collect all class names declared across all fragments of the library.
    final classNames = <String>{};
    for (final fragment in libraryElement.fragments) {
      for (final cls in fragment.classes) {
        final name = cls.name;
        if (name != null) classNames.add(name);
      }
    }

    // MyLibrary is declared in the library file.
    expect(
      classNames,
      contains('MyLibrary'),
      reason:
          'MyLibrary (declared in my_library.dart) must be in the element model',
    );

    // MyLibraryPart is declared in the part file — must be reachable via the
    // library's element model through its fragments.
    expect(
      classNames,
      contains('MyLibraryPart'),
      reason:
          'MyLibraryPart (declared in my_library_part.dart) must be reachable '
          'via the library element model',
    );
  });

  // ---------------------------------------------------------------------------
  // AC4: Overall: no errors in the part fixture (it is a healthy project).
  // ---------------------------------------------------------------------------
  test('AC4: part_fixture produces no errors — it is a healthy project', () {
    expect(
      result.errors,
      isEmpty,
      reason:
          'part_fixture is healthy; errors: '
          '${result.errors.map((e) => '${p.basename(e.path)}: ${e.reason}').toList()}',
    );
  });

  // ---------------------------------------------------------------------------
  // Structural: the library file appears exactly once in resolved.
  // ---------------------------------------------------------------------------
  test('structural: my_library.dart appears exactly once in resolved', () {
    final libraryEntries = result.resolved
        .where((f) => p.basename(f.path) == 'my_library.dart')
        .toList();
    expect(
      libraryEntries.length,
      equals(1),
      reason: 'my_library.dart must appear exactly once in resolved',
    );
  });
}

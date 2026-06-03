@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Resolve fixture paths relative to packages/loam_cli/ (dart test CWD).
  final brokenFixturePath = p.normalize(
    p.join(Directory.current.path, 'test', 'fixtures', 'broken_fixture'),
  );

  // ---------------------------------------------------------------------------
  // AC1 + AC2 + AC4: Broken fixture — no throw; broken file in errors; healthy
  //                  file in resolved with element model.
  // ---------------------------------------------------------------------------
  group('broken_fixture', () {
    late ProjectLoadResult result;

    setUpAll(() async {
      final loader = ProjectLoader();
      result = await loader.load(brokenFixturePath);
    });

    // AC1: Loader does not throw; broken file appears in error branch with path
    //      and a non-empty reason.
    test('AC1: load() does not throw and broken.dart appears in errors with '
        'a reason', () {
      expect(result, isA<ProjectLoadResult>());
      expect(
        result.errors,
        isNotEmpty,
        reason: 'broken.dart must produce an error entry',
      );

      final brokenEntry = result.errors.firstWhere(
        (e) => p.basename(e.path) == 'broken.dart',
        orElse: () => throw StateError('broken.dart not found in errors'),
      );

      expect(
        brokenEntry.path,
        isNotEmpty,
        reason: 'error entry must carry the file path',
      );
      expect(
        p.isAbsolute(brokenEntry.path),
        isTrue,
        reason: 'error path must be absolute',
      );
      expect(
        brokenEntry.reason,
        isNotEmpty,
        reason: 'error entry must carry a non-empty reason',
      );
    });

    // AC2: Healthy file in same fixture appears in resolved with element model.
    test('AC2: healthy.dart from the same fixture appears in resolved with '
        'libraryElement', () {
      expect(
        result.resolved,
        isNotEmpty,
        reason: 'healthy.dart must be resolved',
      );

      final healthyEntry = result.resolved.firstWhere(
        (f) => p.basename(f.path) == 'healthy.dart',
        orElse: () => throw StateError('healthy.dart not found in resolved'),
      );

      expect(
        healthyEntry.result.libraryElement,
        isNotNull,
        reason: 'healthy.dart must have a libraryElement',
      );
      expect(
        healthyEntry.isUnderLib,
        isTrue,
        reason: 'healthy.dart is under lib/',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC3: Non-existent root — typed non-crashing failure (no unhandled stack).
  // ---------------------------------------------------------------------------
  test('AC3: non-existent project root returns a typed error result without '
      'throwing', () async {
    final loader = ProjectLoader();
    final nonExistent = '/this/path/does/not/exist/at/all';

    // Must not throw — returns a ProjectLoadResult with an error entry.
    final result = await loader.load(nonExistent);

    expect(result, isA<ProjectLoadResult>());
    expect(result.resolved, isEmpty);
    expect(
      result.errors,
      isNotEmpty,
      reason: 'non-existent root must produce at least one error entry',
    );
    expect(
      result.errors.first.reason,
      isNotEmpty,
      reason: 'error entry for missing root must carry a reason',
    );
  });

  // ---------------------------------------------------------------------------
  // AC4 (structural): errors list uses LoadFileError (typed), not raw Strings.
  // ---------------------------------------------------------------------------
  test(
    'AC4: ProjectLoadResult.errors contains LoadFileError instances',
    () async {
      final loader = ProjectLoader();
      final result = await loader.load(brokenFixturePath);

      // Type check: every entry in errors must be a LoadFileError.
      for (final entry in result.errors) {
        expect(entry, isA<LoadFileError>());
      }
    },
  );
}

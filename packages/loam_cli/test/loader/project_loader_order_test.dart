@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  // Resolve the fixture path relative to packages/loam_cli/ (dart test CWD).
  final fixturePath = p.normalize(
    p.join(Directory.current.path, 'test', 'fixtures', 'cross_file_fixture'),
  );

  // ---------------------------------------------------------------------------
  // AC1 + AC2: resolved list is sorted by normalised absolute path and two
  //            consecutive runs produce identical order (Invariante 5).
  // ---------------------------------------------------------------------------
  test(
    'AC1: resolved entries are sorted by normalised absolute path',
    () async {
      final loader = ProjectLoader();
      final result = await loader.load(fixturePath);

      final paths = result.resolved.map((f) => f.path).toList();
      final sorted = [...paths]..sort();

      expect(
        paths,
        equals(sorted),
        reason: 'resolved list must be sorted by normalised absolute path',
      );
    },
  );

  test(
    'AC2: two consecutive runs produce identical resolved order (Invariante 5)',
    () async {
      final loader = ProjectLoader();
      final run1 = await loader.load(fixturePath);
      final run2 = await loader.load(fixturePath);

      final paths1 = run1.resolved.map((f) => f.path).toList();
      final paths2 = run2.resolved.map((f) => f.path).toList();

      expect(
        paths1,
        equals(paths2),
        reason: 'Two consecutive runs must produce identical resolved order',
      );
    },
  );

  test(
    'AC3: errors list is also sorted by path (Invariante 5 — full result identity)',
    () async {
      final brokenFixturePath = p.normalize(
        p.join(Directory.current.path, 'test', 'fixtures', 'broken_fixture'),
      );

      final loader = ProjectLoader();
      final run1 = await loader.load(brokenFixturePath);
      final run2 = await loader.load(brokenFixturePath);

      final errorPaths1 = run1.errors.map((e) => e.path).toList();
      final errorPaths2 = run2.errors.map((e) => e.path).toList();

      // Sorted assertion.
      final sortedPaths = [...errorPaths1]..sort();
      expect(
        errorPaths1,
        equals(sortedPaths),
        reason: 'errors list must be sorted by normalised absolute path',
      );

      // Reproducibility assertion.
      expect(
        errorPaths1,
        equals(errorPaths2),
        reason:
            'Two consecutive runs must produce identical errors order '
            '(Invariante 5)',
      );
    },
  );
}

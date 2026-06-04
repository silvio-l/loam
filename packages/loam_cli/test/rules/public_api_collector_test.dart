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
}

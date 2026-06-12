@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/complexity/complexity_metrics.dart';
import 'package:loam/src/complexity/function_complexity_collector.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _fixturePath = p.normalize(
  p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'complexity_collector_fixture',
  ),
);

/// Loads the fixture and returns a fresh [ProjectLoadResult].
/// Asserts that the fixture itself loads without fatal errors.
Future<ProjectLoadResult> _loadFixture() async {
  final loader = const ProjectLoader();
  return loader.load(_fixturePath);
}

/// Shorthand for building a [FunctionComplexityCollector] and calling collect.
List<FunctionComplexity> _collect(ProjectLoadResult result) =>
    const FunctionComplexityCollector().collect(result, _fixturePath);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  late ProjectLoadResult loadResult;

  setUpAll(() async {
    loadResult = await _loadFixture();
    // The fixture must load cleanly (no analysis errors).
    expect(
      loadResult.errors.where((e) => !e.path.endsWith('.g.dart')).toList(),
      isEmpty,
      reason:
          'Fixture must load cleanly (ignoring known generated-file errors)',
    );
  });

  // -------------------------------------------------------------------------
  // AC1: FunctionComplexity is an immutable value object
  // -------------------------------------------------------------------------

  group('FunctionComplexity value object', () {
    test('equality is value-based', () {
      const a = FunctionComplexity(
        qualifiedName: 'foo',
        filePath: 'lib/foo.dart',
        line: 1,
        metrics: ComplexityMetrics(cyclomatic: 2, cognitive: 1),
      );
      const b = FunctionComplexity(
        qualifiedName: 'foo',
        filePath: 'lib/foo.dart',
        line: 1,
        metrics: ComplexityMetrics(cyclomatic: 2, cognitive: 1),
      );
      const c = FunctionComplexity(
        qualifiedName: 'bar',
        filePath: 'lib/foo.dart',
        line: 1,
        metrics: ComplexityMetrics(cyclomatic: 2, cognitive: 1),
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('hashCode is consistent with equality', () {
      const a = FunctionComplexity(
        qualifiedName: 'foo',
        filePath: 'lib/foo.dart',
        line: 1,
        metrics: ComplexityMetrics(cyclomatic: 3, cognitive: 2),
      );
      const b = FunctionComplexity(
        qualifiedName: 'foo',
        filePath: 'lib/foo.dart',
        line: 1,
        metrics: ComplexityMetrics(cyclomatic: 3, cognitive: 2),
      );
      expect(a.hashCode, equals(b.hashCode));
    });

    test('toString is deterministic', () {
      const m = FunctionComplexity(
        qualifiedName: 'Calculator.factorial',
        filePath: 'lib/calculator.dart',
        line: 42,
        metrics: ComplexityMetrics(cyclomatic: 3, cognitive: 2),
      );
      expect(m.toString(), m.toString());
      expect(m.toString(), contains('Calculator.factorial'));
    });
  });

  // -------------------------------------------------------------------------
  // AC2: enumeration — top-level functions, methods, constructors,
  //       non-trivial getters/setters; local functions NOT counted separately
  // -------------------------------------------------------------------------

  group('enumeration of executables', () {
    late List<FunctionComplexity> results;

    setUpAll(() {
      results = _collect(loadResult);
    });

    test('top-level functions are collected', () {
      final names = results.map((r) => r.qualifiedName).toSet();
      expect(names, contains('topLevelSimple'));
      expect(names, contains('topLevelWithBranch'));
    });

    test('class methods are collected', () {
      final names = results.map((r) => r.qualifiedName).toSet();
      expect(names, contains('Calculator.add'));
      expect(names, contains('Calculator.factorial'));
    });

    test('unnamed constructor is collected as ClassName.new', () {
      final names = results.map((r) => r.qualifiedName).toSet();
      expect(names, contains('Calculator.new'));
    });

    test('named constructor is collected', () {
      final names = results.map((r) => r.qualifiedName).toSet();
      expect(names, contains('Calculator.fromPositive'));
    });

    test('getter with non-trivial body is collected', () {
      final names = results.map((r) => r.qualifiedName).toSet();
      expect(names, contains('Calculator.value'));
    });

    test('setter with non-trivial body is collected with = suffix', () {
      final names = results.map((r) => r.qualifiedName).toSet();
      expect(names, contains('Calculator.value='));
    });
  });

  // -------------------------------------------------------------------------
  // AC3: only isUnderLib + non-generated files included
  // -------------------------------------------------------------------------

  group('file filtering', () {
    late List<FunctionComplexity> results;

    setUpAll(() {
      results = _collect(loadResult);
    });

    test('generated file symbols are excluded (*.g.dart)', () {
      final names = results.map((r) => r.qualifiedName).toSet();
      expect(names, isNot(contains('generatedFunction')));
      expect(names, isNot(contains('GeneratedClass.generatedMethod')));
    });

    test('bin/ file symbols are INCLUDED by default (lib + bin)', () {
      // main() is defined in bin/main.dart — included under the default scope.
      final names = results.map((r) => r.qualifiedName).toSet();
      expect(names, contains('main'));
    });

    test('all default results are under lib/ or bin/', () {
      for (final r in results) {
        expect(
          r.filePath.startsWith('lib/') || r.filePath.startsWith('bin/'),
          isTrue,
          reason:
              '${r.qualifiedName} at ${r.filePath} is not under lib/ or bin/',
        );
      }
    });

    test('sourceDirs can be narrowed to lib/ only (excludes bin/)', () {
      final libOnly = const FunctionComplexityCollector().collect(
        loadResult,
        _fixturePath,
        sourceDirs: const ['lib'],
      );
      final names = libOnly.map((r) => r.qualifiedName).toSet();
      expect(names, isNot(contains('main')));
      for (final r in libOnly) {
        expect(r.filePath.startsWith('lib/'), isTrue);
      }
    });

    test('generated files stay excluded regardless of sourceDirs', () {
      final wideScope = const FunctionComplexityCollector().collect(
        loadResult,
        _fixturePath,
        sourceDirs: const ['lib', 'bin', 'test'],
      );
      final names = wideScope.map((r) => r.qualifiedName).toSet();
      expect(names, isNot(contains('generatedFunction')));
    });
  });

  // -------------------------------------------------------------------------
  // AC4: part/augment fragments — no double-counting
  // -------------------------------------------------------------------------

  group('part file — no double-counting', () {
    late List<FunctionComplexity> results;

    setUpAll(() {
      results = _collect(loadResult);
    });

    test('PartHelper.greet appears exactly once', () {
      final count = results
          .where((r) => r.qualifiedName == 'PartHelper.greet')
          .length;
      expect(count, 1, reason: 'PartHelper.greet must appear exactly once');
    });

    test('PartHelper.greetOrFallback appears exactly once', () {
      final count = results
          .where((r) => r.qualifiedName == 'PartHelper.greetOrFallback')
          .length;
      expect(
        count,
        1,
        reason: 'PartHelper.greetOrFallback must appear exactly once',
      );
    });
  });

  // -------------------------------------------------------------------------
  // AC5: deterministic sort — two runs ⇒ identical list
  // -------------------------------------------------------------------------

  group('determinism', () {
    test('two collect calls return identical lists', () async {
      final result1 = await _loadFixture();
      final result2 = await _loadFixture();
      final list1 = const FunctionComplexityCollector().collect(
        result1,
        _fixturePath,
      );
      final list2 = const FunctionComplexityCollector().collect(
        result2,
        _fixturePath,
      );
      expect(list1.length, equals(list2.length));
      for (var i = 0; i < list1.length; i++) {
        expect(
          list1[i],
          equals(list2[i]),
          reason: 'Entry $i differs between two runs',
        );
      }
    });

    test('results are sorted by filePath → line → qualifiedName', () {
      final results = _collect(loadResult);
      for (var i = 1; i < results.length; i++) {
        final prev = results[i - 1];
        final cur = results[i];
        final pathCmp = prev.filePath.compareTo(cur.filePath);
        if (pathCmp < 0) continue;
        if (pathCmp > 0) {
          fail(
            'Sort violated at index $i: '
            '${prev.filePath} > ${cur.filePath}',
          );
        }
        // Same path — check line order.
        if (prev.line < cur.line) continue;
        if (prev.line > cur.line) {
          fail(
            'Sort violated at index $i: '
            '${prev.qualifiedName} (line ${prev.line}) > '
            '${cur.qualifiedName} (line ${cur.line})',
          );
        }
        // Same path + line — check qualifiedName order.
        expect(
          prev.qualifiedName.compareTo(cur.qualifiedName),
          lessThanOrEqualTo(0),
          reason:
              'qualifiedName sort violated at index $i: '
              '${prev.qualifiedName} vs ${cur.qualifiedName}',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // AC6: robustness — non-empty errors → no crash, resolvable files measured
  // -------------------------------------------------------------------------

  group('robustness with errors', () {
    test(
      'non-empty errors in ProjectLoadResult does not crash; lib files measured',
      () async {
        // Use the broken_fixture which has a file with syntax errors.
        final brokenFixturePath = p.normalize(
          p.join(Directory.current.path, 'test', 'fixtures', 'broken_fixture'),
        );
        final loader = const ProjectLoader();
        final result = await loader.load(brokenFixturePath);

        // Sanity: broken_fixture must have at least one error.
        expect(result.errors, isNotEmpty);

        // Must not throw.
        late final List<FunctionComplexity> results;
        expect(() {
          results = const FunctionComplexityCollector().collect(
            result,
            brokenFixturePath,
          );
        }, returnsNormally);

        // Healthy lib file must still be measured.
        final names = results.map((r) => r.qualifiedName).toSet();
        expect(names, contains('HealthyClass.greet'));
      },
    );
  });

  // -------------------------------------------------------------------------
  // AC7: concrete metric numbers for the fixture
  // -------------------------------------------------------------------------

  group('concrete metrics', () {
    late List<FunctionComplexity> results;
    late Map<String, FunctionComplexity> byName;

    setUpAll(() {
      results = _collect(loadResult);
      byName = {for (final r in results) r.qualifiedName: r};
    });

    test('topLevelSimple: cyclomatic=1, cognitive=0', () {
      final r = byName['topLevelSimple']!;
      expect(r.metrics, const ComplexityMetrics(cyclomatic: 1, cognitive: 0));
    });

    test('topLevelWithBranch: cyclomatic=2, cognitive=1', () {
      final r = byName['topLevelWithBranch']!;
      expect(r.metrics, const ComplexityMetrics(cyclomatic: 2, cognitive: 1));
    });

    test('Calculator.new: cyclomatic=1, cognitive=0', () {
      final r = byName['Calculator.new']!;
      expect(r.metrics, const ComplexityMetrics(cyclomatic: 1, cognitive: 0));
    });

    test('Calculator.fromPositive: cyclomatic=2, cognitive=1', () {
      final r = byName['Calculator.fromPositive']!;
      expect(r.metrics, const ComplexityMetrics(cyclomatic: 2, cognitive: 1));
    });

    test('Calculator.add: cyclomatic=1, cognitive=0', () {
      final r = byName['Calculator.add']!;
      expect(r.metrics, const ComplexityMetrics(cyclomatic: 1, cognitive: 0));
    });

    test('Calculator.factorial: cyclomatic=3, cognitive=2', () {
      final r = byName['Calculator.factorial']!;
      expect(r.metrics, const ComplexityMetrics(cyclomatic: 3, cognitive: 2));
    });

    test('Calculator.value (getter): cyclomatic=1, cognitive=0', () {
      final r = byName['Calculator.value']!;
      expect(r.metrics, const ComplexityMetrics(cyclomatic: 1, cognitive: 0));
    });

    test('Calculator.value= (setter): cyclomatic=2, cognitive=1', () {
      final r = byName['Calculator.value=']!;
      expect(r.metrics, const ComplexityMetrics(cyclomatic: 2, cognitive: 1));
    });

    test('PartHelper.greet: cyclomatic=1, cognitive=0', () {
      final r = byName['PartHelper.greet']!;
      expect(r.metrics, const ComplexityMetrics(cyclomatic: 1, cognitive: 0));
    });

    test('PartHelper.greetOrFallback: cyclomatic=2, cognitive=1', () {
      final r = byName['PartHelper.greetOrFallback']!;
      expect(r.metrics, const ComplexityMetrics(cyclomatic: 2, cognitive: 1));
    });

    test('filePath for lib/calculator.dart entries uses POSIX path', () {
      final r = byName['topLevelSimple']!;
      // Must be relative POSIX path under lib/
      expect(r.filePath, 'lib/calculator.dart');
      expect(r.filePath.contains(r'\'), isFalse);
    });

    test(
      'filePath for part file entries is the part file, not library file',
      () {
        final r = byName['PartHelper.greet']!;
        expect(r.filePath, 'lib/calculator_part.dart');
      },
    );

    test('line numbers are positive (1-based)', () {
      for (final r in results) {
        expect(
          r.line,
          greaterThan(0),
          reason: '${r.qualifiedName} has non-positive line',
        );
      }
    });
  });
}

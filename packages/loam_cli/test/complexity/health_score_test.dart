@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/complexity/complexity_metrics.dart';
import 'package:loam/src/complexity/function_complexity.dart';
import 'package:loam/src/complexity/health_score.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helper factories
// ---------------------------------------------------------------------------

/// Creates a [FunctionComplexity] with the given cyclomatic and cognitive
/// values. Defaults to a unique name/path/line so tests can build lists easily.
FunctionComplexity _fc({
  required int cyclomatic,
  required int cognitive,
  String name = 'fn',
  String path = 'lib/src/a.dart',
  int line = 1,
}) => FunctionComplexity(
  qualifiedName: name,
  filePath: path,
  line: line,
  metrics: ComplexityMetrics(cyclomatic: cyclomatic, cognitive: cognitive),
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final engine = const HealthScore();

  // ---- AC1: HealthReport is an immutable value object ----------------------

  group('HealthReport value object', () {
    test('exposes score, grade, hotspots', () {
      final r = HealthReport(
        score: 85,
        grade: 'B',
        hotspots: [_fc(cyclomatic: 5, cognitive: 3)],
      );
      expect(r.score, 85);
      expect(r.grade, 'B');
      expect(r.hotspots, hasLength(1));
    });

    test('equality is value-based', () {
      final fc = _fc(cyclomatic: 3, cognitive: 2);
      final r1 = HealthReport(score: 90, grade: 'A', hotspots: [fc]);
      final r2 = HealthReport(score: 90, grade: 'A', hotspots: [fc]);
      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));
    });

    test('inequality when score differs', () {
      final fc = _fc(cyclomatic: 3, cognitive: 2);
      final r1 = HealthReport(score: 90, grade: 'A', hotspots: [fc]);
      final r2 = HealthReport(score: 80, grade: 'B', hotspots: [fc]);
      expect(r1, isNot(equals(r2)));
    });

    test('toString mentions score and grade', () {
      final r = HealthReport(score: 70, grade: 'C', hotspots: []);
      expect(r.toString(), contains('70'));
      expect(r.toString(), contains('C'));
    });
  });

  // ---- AC2 (indirectly): grade bands documented and correct ----------------

  group('HealthScore.gradeFor — grade bands', () {
    test('score 100 → A', () => expect(HealthScore.gradeFor(100), 'A'));
    test('score 90  → A', () => expect(HealthScore.gradeFor(90), 'A'));
    test('score 89  → B', () => expect(HealthScore.gradeFor(89), 'B'));
    test('score 75  → B', () => expect(HealthScore.gradeFor(75), 'B'));
    test('score 74  → C', () => expect(HealthScore.gradeFor(74), 'C'));
    test('score 60  → C', () => expect(HealthScore.gradeFor(60), 'C'));
    test('score 59  → D', () => expect(HealthScore.gradeFor(59), 'D'));
    test('score 45  → D', () => expect(HealthScore.gradeFor(45), 'D'));
    test('score 44  → F', () => expect(HealthScore.gradeFor(44), 'F'));
    test('score 0   → F', () => expect(HealthScore.gradeFor(0), 'F'));
  });

  // ---- AC4 unit tests -------------------------------------------------------

  group('HealthScore.compute', () {
    // AC4a: empty list → top score / grade A
    test('empty list returns score 100 and grade A', () {
      final report = engine.compute([]);
      expect(report.score, 100);
      expect(report.grade, 'A');
      expect(report.hotspots, isEmpty);
    });

    // AC4b: all trivial executables → top score / grade A
    test('all trivial (magnitude ≤ threshold) → score 100, grade A', () {
      final fns = [
        _fc(cyclomatic: 1, cognitive: 0, name: 'a', line: 1),
        _fc(cyclomatic: 3, cognitive: 2, name: 'b', line: 2),
        _fc(cyclomatic: 10, cognitive: 5, name: 'c', line: 3),
        // magnitude = max(10,5) = 10 which is exactly the threshold — no penalty
      ];
      final report = engine.compute(fns);
      expect(report.score, 100);
      expect(report.grade, 'A');
    });

    // AC4c: one extreme hotspot → significant score drop
    test('one extreme hotspot causes score to drop below 100', () {
      // 9 trivial + 1 extreme (magnitude 50 → penalty 40)
      final fns = [
        for (var i = 0; i < 9; i++)
          _fc(cyclomatic: 1, cognitive: 0, name: 'fn$i', line: i + 1),
        _fc(cyclomatic: 50, cognitive: 3, name: 'heavy', line: 100),
      ];
      final report = engine.compute(fns);
      // totalPenalty = 40 (clamped), worstCase = 10*40 = 400
      // normalisedPenalty = 40/400 = 0.1 → score = round(90) = 90
      expect(report.score, 90);
      expect(report.grade, 'A');
    });

    test('several heavy executables bring score well below 100', () {
      // 5 executables each with magnitude 30 → penalty 20 each
      // totalPenalty = 5*20 = 100, worstCase = 5*40 = 200
      // normalisedPenalty = 0.5 → score = round(50) = 50
      final fns = [
        for (var i = 0; i < 5; i++)
          _fc(cyclomatic: 30, cognitive: 5, name: 'fn$i', line: i + 1),
      ];
      final report = engine.compute(fns);
      expect(report.score, 50);
      expect(report.grade, 'D');
    });

    test('worst-case single function is clamped correctly', () {
      // One function with magnitude 1000 (far above threshold+40=50).
      // penalty clamped to worstCasePenaltyPerFunction = 40.
      // worstCase = 1*40 = 40 → normalisedPenalty = 1.0 → score = 0.
      final fns = [_fc(cyclomatic: 1000, cognitive: 0, name: 'monster')];
      final report = engine.compute(fns);
      expect(report.score, 0);
      expect(report.grade, 'F');
    });

    // AC4d: grade band boundaries (already covered by gradeFor tests above,
    // but verify compute returns the right grade at boundary scores too)
    test('compute returns grade A at score 90', () {
      // Craft input so score = 90.
      // 10 fns, 1 heavy with magnitude 50 (capped penalty 40):
      // totalPenalty=40, worstCase=400 → score=round(100*0.9)=90 → A
      final fns = [
        for (var i = 0; i < 9; i++)
          _fc(cyclomatic: 1, cognitive: 0, name: 'fn$i', line: i + 1),
        _fc(cyclomatic: 50, cognitive: 3, name: 'heavy', line: 100),
      ];
      final report = engine.compute(fns);
      expect(report.score, 90);
      expect(report.grade, 'A');
    });

    // AC4e: hotspot sorting + tie-break
    test('hotspots are sorted descending by magnitude', () {
      final fns = [
        _fc(cyclomatic: 3, cognitive: 2, name: 'low', line: 1),
        _fc(cyclomatic: 20, cognitive: 5, name: 'high', line: 2),
        _fc(cyclomatic: 10, cognitive: 12, name: 'mid', line: 3),
      ];
      // magnitudes: low=3, high=20, mid=12
      final report = engine.compute(fns);
      expect(report.hotspots.map((h) => h.qualifiedName).toList(), [
        'high',
        'mid',
        'low',
      ]);
    });

    test('tie-break on filePath ascending', () {
      final fns = [
        _fc(
          cyclomatic: 15,
          cognitive: 5,
          name: 'fn',
          path: 'lib/src/z.dart',
          line: 1,
        ),
        _fc(
          cyclomatic: 15,
          cognitive: 5,
          name: 'fn',
          path: 'lib/src/a.dart',
          line: 1,
        ),
      ];
      // Same magnitude (15), tie-break by path: a.dart < z.dart
      final report = engine.compute(fns);
      expect(report.hotspots[0].filePath, 'lib/src/a.dart');
      expect(report.hotspots[1].filePath, 'lib/src/z.dart');
    });

    test('tie-break on line ascending when filePath equals', () {
      final fns = [
        _fc(
          cyclomatic: 15,
          cognitive: 5,
          name: 'fn2',
          path: 'lib/src/a.dart',
          line: 20,
        ),
        _fc(
          cyclomatic: 15,
          cognitive: 5,
          name: 'fn1',
          path: 'lib/src/a.dart',
          line: 5,
        ),
      ];
      final report = engine.compute(fns);
      expect(report.hotspots[0].line, 5);
      expect(report.hotspots[1].line, 20);
    });

    test(
      'tie-break on qualifiedName ascending when filePath and line equal',
      () {
        final fns = [
          _fc(
            cyclomatic: 15,
            cognitive: 5,
            name: 'z_fn',
            path: 'lib/src/a.dart',
            line: 1,
          ),
          _fc(
            cyclomatic: 15,
            cognitive: 5,
            name: 'a_fn',
            path: 'lib/src/a.dart',
            line: 1,
          ),
        ];
        final report = engine.compute(fns);
        expect(report.hotspots[0].qualifiedName, 'a_fn');
        expect(report.hotspots[1].qualifiedName, 'z_fn');
      },
    );

    // AC4f: Top-N cap
    test('hotspots are capped at topN (${HealthScore.topN})', () {
      final fns = [
        for (var i = 0; i < HealthScore.topN + 5; i++)
          _fc(cyclomatic: i + 1, cognitive: 0, name: 'fn$i', line: i + 1),
      ];
      final report = engine.compute(fns);
      expect(report.hotspots, hasLength(HealthScore.topN));
    });

    test('hotspots include whole distribution, not just above threshold', () {
      // All functions below the penalty threshold
      final fns = [
        for (var i = 1; i <= 5; i++)
          _fc(cyclomatic: i, cognitive: 0, name: 'fn$i', line: i),
      ];
      final report = engine.compute(fns);
      // All 5 should appear in hotspots (sorted descending by magnitude)
      expect(report.hotspots, hasLength(5));
      expect(report.hotspots[0].qualifiedName, 'fn5'); // magnitude 5 first
    });
  });

  // ---- AC5: Determinism test ------------------------------------------------

  group('HealthScore determinism', () {
    test('same input twice yields identical HealthReport', () {
      final fns = [
        _fc(
          cyclomatic: 5,
          cognitive: 3,
          name: 'a',
          path: 'lib/src/a.dart',
          line: 10,
        ),
        _fc(
          cyclomatic: 25,
          cognitive: 12,
          name: 'b',
          path: 'lib/src/b.dart',
          line: 5,
        ),
        _fc(
          cyclomatic: 1,
          cognitive: 0,
          name: 'c',
          path: 'lib/src/a.dart',
          line: 1,
        ),
        _fc(
          cyclomatic: 15,
          cognitive: 20,
          name: 'd',
          path: 'lib/src/c.dart',
          line: 3,
        ),
      ];
      final r1 = engine.compute(fns);
      final r2 = engine.compute(fns);
      expect(r1, equals(r2));
      expect(r1.score, equals(r2.score));
      expect(r1.grade, equals(r2.grade));
      expect(r1.hotspots, equals(r2.hotspots));
    });

    test('shuffled input produces same score (penalty is order-independent)', () {
      final fns = [
        _fc(cyclomatic: 5, cognitive: 3, name: 'a', line: 1),
        _fc(cyclomatic: 25, cognitive: 12, name: 'b', line: 2),
        _fc(cyclomatic: 1, cognitive: 0, name: 'c', line: 3),
      ];
      final r1 = engine.compute(fns);
      // Reverse order — score should be identical (penalty sum is commutative).
      final reversed = fns.reversed.toList();
      final r2 = engine.compute(reversed);
      expect(r1.score, equals(r2.score));
      expect(r1.grade, equals(r2.grade));
    });
  });

  // ---- AC1 (immutability): hotspots list is unmodifiable --------------------

  test('HealthReport.hotspots is unmodifiable', () {
    final report = engine.compute([
      _fc(cyclomatic: 5, cognitive: 3, name: 'fn', line: 1),
    ]);
    expect(
      () => report.hotspots.add(_fc(cyclomatic: 1, cognitive: 0)),
      throwsUnsupportedError,
    );
  });

  // ---- AC6/AC7: purity check (no Finding/Reporter/ReportPayload imports) ---
  // Reads the actual source files and asserts forbidden symbols are absent.

  test(
    'health_score.dart and health_report.dart import no forbidden symbols',
    () {
      // Resolve paths relative to this test file's location.
      // test/ is at packages/loam_cli/test/; sources at packages/loam_cli/lib/
      final packageRoot = Directory.current.path.endsWith('loam_cli')
          ? Directory.current.path
          : '${Directory.current.path}/packages/loam_cli';

      final sourceFiles = [
        '$packageRoot/lib/src/complexity/health_score.dart',
        '$packageRoot/lib/src/complexity/health_report.dart',
      ];

      // Patterns are import-line-anchored so doc-comment mentions do not
      // trigger false positives (the class names appear in comments).
      const forbiddenPatterns = [
        "import 'package:loam/src/report/",
        "import '../report/",
        "import 'package:loam/src/model/finding",
        "import '../model/finding",
        "import 'package:loam/src/gate/",
        "import '../gate/",
      ];

      for (final path in sourceFiles) {
        final content = File(path).readAsStringSync();
        for (final pattern in forbiddenPatterns) {
          expect(
            content,
            isNot(contains(pattern)),
            reason: '$path must not reference forbidden symbol: $pattern',
          );
        }
      }
    },
  );
}

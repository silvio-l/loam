@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/complexity/complexity_metrics.dart';
import 'package:loam/src/complexity/function_complexity.dart';
import 'package:loam/src/complexity/health_score.dart';
import 'package:loam/src/model/finding.dart';
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

/// Creates a [Finding] with the given severity. Fingerprint/message are
/// arbitrary — only severity matters for the health-score formula.
Finding _finding({
  Severity severity = Severity.warning,
  String ruleId = 'slop-empty-catch',
  String filePath = 'lib/src/a.dart',
  int line = 1,
  String message = 'finding',
}) => Finding(
  ruleId: ruleId,
  severity: severity,
  filePath: filePath,
  line: line,
  message: message,
  fingerprint: '$ruleId:$filePath:$line:${identityHashCode(message)}',
);

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  final engine = const HealthScore();

  // ---- HealthReport value object --------------------------------------------

  group('HealthReport value object', () {
    test('exposes score, grade, contributions, hotspots', () {
      final r = HealthReport(
        score: 85,
        grade: 'B',
        hotspots: [_fc(cyclomatic: 5, cognitive: 3)],
        findingsContribution: 90,
        complexityContribution: 80,
      );
      expect(r.score, 85);
      expect(r.grade, 'B');
      expect(r.hotspots, hasLength(1));
      expect(r.findingsContribution, 90);
      expect(r.complexityContribution, 80);
    });

    test('equality is value-based', () {
      final fc = _fc(cyclomatic: 3, cognitive: 2);
      final r1 = HealthReport(
        score: 90,
        grade: 'A',
        hotspots: [fc],
        findingsContribution: 100,
        complexityContribution: 80,
      );
      final r2 = HealthReport(
        score: 90,
        grade: 'A',
        hotspots: [fc],
        findingsContribution: 100,
        complexityContribution: 80,
      );
      expect(r1, equals(r2));
      expect(r1.hashCode, equals(r2.hashCode));
    });

    test('inequality when score differs', () {
      final fc = _fc(cyclomatic: 3, cognitive: 2);
      final r1 = HealthReport(
        score: 90,
        grade: 'A',
        hotspots: [fc],
        findingsContribution: 100,
        complexityContribution: 80,
      );
      final r2 = HealthReport(
        score: 80,
        grade: 'B',
        hotspots: [fc],
        findingsContribution: 100,
        complexityContribution: 60,
      );
      expect(r1, isNot(equals(r2)));
    });

    test('inequality when only a contribution differs', () {
      final fc = _fc(cyclomatic: 3, cognitive: 2);
      final r1 = HealthReport(
        score: 90,
        grade: 'A',
        hotspots: [fc],
        findingsContribution: 100,
        complexityContribution: 80,
      );
      final r2 = HealthReport(
        score: 90,
        grade: 'A',
        hotspots: [fc],
        findingsContribution: 95,
        complexityContribution: 80,
      );
      expect(r1, isNot(equals(r2)));
    });

    test('toString mentions score, grade, and contributions', () {
      final r = HealthReport(
        score: 70,
        grade: 'C',
        hotspots: [],
        findingsContribution: 65,
        complexityContribution: 78,
      );
      expect(r.toString(), contains('70'));
      expect(r.toString(), contains('C'));
      expect(r.toString(), contains('findingsContribution: 65'));
      expect(r.toString(), contains('complexityContribution: 78'));
    });
  });

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

  // ---- Composite score: baseline behaviour -----------------------------------

  group('HealthScore.compute — baseline (no findings, no functions)', () {
    test('empty functions + empty findings → score 100, grade A', () {
      final report = engine.compute([], findings: [], linesAnalyzed: 1000);
      expect(report.score, 100);
      expect(report.grade, 'A');
      expect(report.hotspots, isEmpty);
      expect(report.findingsContribution, 100);
      expect(report.complexityContribution, 100);
    });

    test('zero findings + low complexity → score ~100, grade A '
        '(acceptance criterion)', () {
      final fns = [
        _fc(cyclomatic: 1, cognitive: 0, name: 'a', line: 1),
        _fc(cyclomatic: 3, cognitive: 2, name: 'b', line: 2),
        _fc(cyclomatic: 10, cognitive: 5, name: 'c', line: 3),
      ];
      final report = engine.compute(
        fns,
        findings: const [],
        linesAnalyzed: 5000,
      );
      expect(report.score, greaterThanOrEqualTo(95));
      expect(report.grade, 'A');
    });

    test('linesAnalyzed of 0 does not throw and stays well-defined', () {
      final report = engine.compute([], findings: [], linesAnalyzed: 0);
      expect(report.score, 100);
      expect(report.grade, 'A');
    });
  });

  // ---- Composite score: findings axis ----------------------------------------

  group('HealthScore.compute — findings axis', () {
    test('150+ findings at moderate complexity → no Grade A '
        '(HellerIO regression — acceptance criterion)', () {
      final findings = [
        for (var i = 0; i < 150; i++)
          _finding(
            severity: i % 3 == 0 ? Severity.error : Severity.warning,
            line: i + 1,
          ),
      ];
      final fns = [
        for (var i = 0; i < 20; i++)
          _fc(cyclomatic: 6, cognitive: 4, name: 'fn$i', line: i + 1),
      ];
      final report = engine.compute(
        fns,
        findings: findings,
        linesAnalyzed: 15000,
      );
      expect(
        report.grade,
        isNot('A'),
        reason: '150+ findings must never score Grade A',
      );
      expect(report.score, lessThan(90));
    });

    test(
      'severity weighting: error drags the score down more than warning',
      () {
        final errorFindings = List.generate(
          20,
          (i) => _finding(severity: Severity.error, line: i + 1),
        );
        final warningFindings = List.generate(
          20,
          (i) => _finding(severity: Severity.warning, line: i + 1),
        );
        final reportError = engine.compute(
          [],
          findings: errorFindings,
          linesAnalyzed: 10000,
        );
        final reportWarning = engine.compute(
          [],
          findings: warningFindings,
          linesAnalyzed: 10000,
        );
        expect(
          reportError.findingsContribution,
          lessThan(reportWarning.findingsContribution),
          reason: 'error findings must weigh more than warning findings',
        );
      },
    );

    test('severity weighting: warning drags the score down more than info', () {
      final warningFindings = List.generate(
        20,
        (i) => _finding(severity: Severity.warning, line: i + 1),
      );
      final infoFindings = List.generate(
        20,
        (i) => _finding(severity: Severity.info, line: i + 1),
      );
      final reportWarning = engine.compute(
        [],
        findings: warningFindings,
        linesAnalyzed: 10000,
      );
      final reportInfo = engine.compute(
        [],
        findings: infoFindings,
        linesAnalyzed: 10000,
      );
      expect(
        reportWarning.findingsContribution,
        lessThan(reportInfo.findingsContribution),
        reason: 'warning findings must weigh more than info findings',
      );
    });

    test('size normalisation: same finding count scores worse in a small repo '
        'than in a large one (acceptance criterion)', () {
      final findings = List.generate(
        30,
        (i) => _finding(severity: Severity.warning, line: i + 1),
      );
      final smallRepo = engine.compute(
        [],
        findings: findings,
        linesAnalyzed: 2000,
      );
      final largeRepo = engine.compute(
        [],
        findings: findings,
        linesAnalyzed: 200000,
      );
      expect(
        smallRepo.findingsContribution,
        lessThan(largeRepo.findingsContribution),
        reason:
            'the same finding count must be denser (worse) in a smaller repo',
      );
      expect(smallRepo.score, lessThan(largeRepo.score));
    });

    test('no findings → findingsContribution is 100 regardless of size', () {
      final report = engine.compute([], findings: [], linesAnalyzed: 42);
      expect(report.findingsContribution, 100);
    });
  });

  // ---- Composite score: complexity axis --------------------------------------

  group('HealthScore.compute — complexity axis', () {
    test('a few brutal hotspots in a large repo cause a noticeable penalty, '
        'not diluted by N (acceptance criterion)', () {
      // 500 trivial functions + 3 brutal hotspots (magnitude 50 each).
      final fns = [
        for (var i = 0; i < 500; i++)
          _fc(cyclomatic: 2, cognitive: 1, name: 'trivial$i', line: i + 1),
        _fc(cyclomatic: 50, cognitive: 3, name: 'brutal1', line: 501),
        _fc(cyclomatic: 50, cognitive: 3, name: 'brutal2', line: 502),
        _fc(cyclomatic: 50, cognitive: 3, name: 'brutal3', line: 503),
      ];
      final report = engine.compute(
        fns,
        findings: const [],
        linesAnalyzed: 50000,
      );
      // totalPenalty = 3 * 40 = 120, fixed budget = 200 →
      // complexityContribution = round(100*(1-120/200)) = 40.
      expect(report.complexityContribution, 40);
      expect(
        report.complexityContribution,
        lessThan(70),
        reason:
            'a handful of brutal hotspots must not be averaged away by a '
            'huge N',
      );
    });

    test('the same hotspots produce the same complexityContribution '
        'regardless of how many trivial functions surround them', () {
      final hotspots = [
        _fc(cyclomatic: 50, cognitive: 3, name: 'brutal1', line: 1),
        _fc(cyclomatic: 50, cognitive: 3, name: 'brutal2', line: 2),
      ];
      final smallProject = engine.compute(
        hotspots,
        findings: const [],
        linesAnalyzed: 5000,
      );
      final bigProject = engine.compute(
        [
          ...hotspots,
          for (var i = 0; i < 5000; i++)
            _fc(cyclomatic: 1, cognitive: 0, name: 'trivial$i', line: i + 3),
        ],
        findings: const [],
        linesAnalyzed: 500000,
      );
      expect(
        smallProject.complexityContribution,
        equals(bigProject.complexityContribution),
        reason:
            'hotspots must be weighed absolutely, not diluted by the '
            'total function count',
      );
    });

    test('all trivial (magnitude ≤ threshold) → complexityContribution 100', () {
      final fns = [
        _fc(cyclomatic: 1, cognitive: 0, name: 'a', line: 1),
        _fc(cyclomatic: 3, cognitive: 2, name: 'b', line: 2),
        _fc(cyclomatic: 10, cognitive: 5, name: 'c', line: 3),
        // magnitude = max(10,5) = 10 which is exactly the threshold — no penalty
      ];
      final report = engine.compute(
        fns,
        findings: const [],
        linesAnalyzed: 1000,
      );
      expect(report.complexityContribution, 100);
    });

    test('worst-case single function is clamped correctly '
        '(complexityContribution bottoms out)', () {
      final fns = [_fc(cyclomatic: 1000, cognitive: 0, name: 'monster')];
      final report = engine.compute(
        fns,
        findings: const [],
        linesAnalyzed: 1000,
      );
      // Single-function penalty is clamped to 40, budget is 200 →
      // complexityContribution = round(100*(1-40/200)) = 80.
      expect(report.complexityContribution, 80);
    });
  });

  // ---- Composite score: combination + hard cap -------------------------------

  group('HealthScore.compute — combination and hard cap', () {
    test('the hard cap actually binds: moderate finding density with a perfect '
        'complexity axis would reach Grade A under the weighted formula alone, '
        'but the hard cap pulls it down to Grade B', () {
      // 25 error findings over 20,000 lines → density 6.25, which is
      // ≥ substantialDensityThreshold (5) but low enough that the weighted
      // combination alone (findingsContribution 84, complexityContribution
      // 100) would still round to 90 (Grade A) without the cap.
      final findings = List.generate(
        25,
        (i) => _finding(severity: Severity.error, line: i + 1),
      );
      final report = engine.compute(
        [], // no complexity penalty at all
        findings: findings,
        linesAnalyzed: 20000,
      );
      expect(report.complexityContribution, 100);
      expect(report.findingsContribution, 84);
      expect(
        report.score,
        equals(HealthScore.hardCapScore),
        reason:
            'the weighted formula alone would round to 90 here — the hard '
            'cap must pull it down to 89',
      );
      expect(report.grade, isNot('A'));
    });

    test(
      'a very high finding density hard-caps the score well below Grade A',
      () {
        final findings = List.generate(
          60,
          (i) => _finding(severity: Severity.error, line: i + 1),
        );
        final report = engine.compute(
          [], // no complexity penalty at all
          findings: findings,
          linesAnalyzed: 10000,
        );
        expect(report.complexityContribution, 100);
        expect(report.score, lessThanOrEqualTo(HealthScore.hardCapScore));
        expect(report.grade, isNot('A'));
      },
    );

    test(
      'light finding load below the substantial threshold is not capped',
      () {
        final findings = [_finding(severity: Severity.info, line: 1)];
        final report = engine.compute(
          [],
          findings: findings,
          linesAnalyzed: 100000,
        );
        expect(report.score, 100);
        expect(report.grade, 'A');
      },
    );
  });

  // ---- Hotspot list behaviour (unchanged surface) -----------------------------

  group('HealthScore.compute — hotspot list', () {
    test('hotspots are sorted descending by magnitude', () {
      final fns = [
        _fc(cyclomatic: 3, cognitive: 2, name: 'low', line: 1),
        _fc(cyclomatic: 20, cognitive: 5, name: 'high', line: 2),
        _fc(cyclomatic: 10, cognitive: 12, name: 'mid', line: 3),
      ];
      final report = engine.compute(
        fns,
        findings: const [],
        linesAnalyzed: 1000,
      );
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
      final report = engine.compute(
        fns,
        findings: const [],
        linesAnalyzed: 1000,
      );
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
      final report = engine.compute(
        fns,
        findings: const [],
        linesAnalyzed: 1000,
      );
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
        final report = engine.compute(
          fns,
          findings: const [],
          linesAnalyzed: 1000,
        );
        expect(report.hotspots[0].qualifiedName, 'a_fn');
        expect(report.hotspots[1].qualifiedName, 'z_fn');
      },
    );

    test('hotspots are capped at topN (${HealthScore.topN})', () {
      final fns = [
        for (var i = 0; i < HealthScore.topN + 5; i++)
          _fc(cyclomatic: i + 1, cognitive: 0, name: 'fn$i', line: i + 1),
      ];
      final report = engine.compute(
        fns,
        findings: const [],
        linesAnalyzed: 1000,
      );
      expect(report.hotspots, hasLength(HealthScore.topN));
    });

    test('hotspots include whole distribution, not just above threshold', () {
      final fns = [
        for (var i = 1; i <= 5; i++)
          _fc(cyclomatic: i, cognitive: 0, name: 'fn$i', line: i),
      ];
      final report = engine.compute(
        fns,
        findings: const [],
        linesAnalyzed: 1000,
      );
      expect(report.hotspots, hasLength(5));
      expect(report.hotspots[0].qualifiedName, 'fn5'); // magnitude 5 first
    });
  });

  // ---- Determinism ------------------------------------------------------------

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
      final findings = [
        _finding(severity: Severity.error, line: 1),
        _finding(severity: Severity.warning, line: 2),
        _finding(severity: Severity.info, line: 3),
      ];
      final r1 = engine.compute(fns, findings: findings, linesAnalyzed: 8000);
      final r2 = engine.compute(fns, findings: findings, linesAnalyzed: 8000);
      expect(r1, equals(r2));
      expect(r1.score, equals(r2.score));
      expect(r1.grade, equals(r2.grade));
      expect(r1.findingsContribution, equals(r2.findingsContribution));
      expect(r1.complexityContribution, equals(r2.complexityContribution));
      expect(r1.hotspots, equals(r2.hotspots));
    });

    test('shuffled functions and findings produce the same score '
        '(sums are order-independent)', () {
      final fns = [
        _fc(cyclomatic: 5, cognitive: 3, name: 'a', line: 1),
        _fc(cyclomatic: 25, cognitive: 12, name: 'b', line: 2),
        _fc(cyclomatic: 1, cognitive: 0, name: 'c', line: 3),
      ];
      final findings = [
        _finding(severity: Severity.error, line: 1),
        _finding(severity: Severity.warning, line: 2),
      ];
      final r1 = engine.compute(fns, findings: findings, linesAnalyzed: 3000);
      final r2 = engine.compute(
        fns.reversed.toList(),
        findings: findings.reversed.toList(),
        linesAnalyzed: 3000,
      );
      expect(r1.score, equals(r2.score));
      expect(r1.grade, equals(r2.grade));
      expect(r1.findingsContribution, equals(r2.findingsContribution));
      expect(r1.complexityContribution, equals(r2.complexityContribution));
    });
  });

  // ---- Immutability -------------------------------------------------------

  test('HealthReport.hotspots is unmodifiable', () {
    final report = engine.compute(
      [_fc(cyclomatic: 5, cognitive: 3, name: 'fn', line: 1)],
      findings: const [],
      linesAnalyzed: 1000,
    );
    expect(
      () => report.hotspots.add(_fc(cyclomatic: 1, cognitive: 0)),
      throwsUnsupportedError,
    );
  });

  // ---- Purity check: no Reporter/ReportPayload dependency --------------------
  //
  // The module DOES depend on `Finding` (it is a required `compute()`
  // parameter per this ticket) — that is intentional and no longer forbidden.
  // What stays forbidden is any dependency on the Reporter/ReportPayload/gate
  // layers, keeping this module a pure aggregation module.

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

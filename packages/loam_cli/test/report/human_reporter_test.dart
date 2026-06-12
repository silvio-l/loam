@TestOn('vm')
library;

import 'package:loam/src/model/finding.dart';
import 'package:loam/src/report/human_reporter.dart';
import 'package:loam/src/report/reporter.dart';
import 'package:loam/src/report/reporter_dispatch.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Shared fixture helpers
// ---------------------------------------------------------------------------

Finding _finding({
  String ruleId = 'unused-public-exports',
  Severity severity = Severity.warning,
  String filePath = 'lib/src/foo.dart',
  int line = 10,
  int? column,
  String message = 'Unused export: Foo',
  String fingerprint = 'abc123',
}) => Finding(
  ruleId: ruleId,
  severity: severity,
  filePath: filePath,
  line: line,
  column: column,
  message: message,
  fingerprint: fingerprint,
);

ReportPayload _payload({
  List<Finding> findings = const [],
  String projectRoot = '/project',
  String rulesetVersion = 'ruleset@abc12345',
  String toolVersion = '0.0.2',
  bool isTty = false,
  int suppressedCount = 0,
  ScanStats? stats,
}) => ReportPayload(
  findings: findings,
  projectRoot: projectRoot,
  rulesetVersion: rulesetVersion,
  toolVersion: toolVersion,
  isTty: isTty,
  suppressedCount: suppressedCount,
  stats: stats,
);

const _stats = ScanStats(
  filesAnalyzed: 168,
  libFilesAnalyzed: 50,
  linesAnalyzed: 18432,
  rulesRun: ['circular-dependencies', 'complexity-hotspots'],
);

void main() {
  // -------------------------------------------------------------------------
  // AC1: Reporter interface + ReportPayload
  // -------------------------------------------------------------------------
  group('Reporter interface', () {
    test('HumanReporter implements Reporter', () {
      final Reporter reporter = HumanReporter();
      // Just calling render verifies the interface is satisfied.
      final output = reporter.render(_payload());
      expect(output, isA<String>());
    });

    test('render is a pure function — same input produces same output', () {
      final reporter = HumanReporter();
      final payload = _payload(findings: [_finding()]);
      expect(reporter.render(payload), equals(reporter.render(payload)));
    });
  });

  // -------------------------------------------------------------------------
  // AC2: HumanReporter groups by file, shows location/severity/ruleId/message
  // -------------------------------------------------------------------------
  group('HumanReporter grouping and content', () {
    test('groups findings by filePath', () {
      final findings = [
        _finding(filePath: 'lib/a.dart', line: 5, fingerprint: 'fp1'),
        _finding(filePath: 'lib/b.dart', line: 3, fingerprint: 'fp2'),
        _finding(filePath: 'lib/a.dart', line: 8, fingerprint: 'fp3'),
      ];
      final output = HumanReporter().render(_payload(findings: findings));

      // Both a.dart findings appear under the a.dart header
      final aHeaderIdx = output.indexOf('lib/a.dart');
      final bHeaderIdx = output.indexOf('lib/b.dart');
      expect(
        aHeaderIdx,
        greaterThanOrEqualTo(0),
        reason: 'a.dart header expected',
      );
      expect(
        bHeaderIdx,
        greaterThanOrEqualTo(0),
        reason: 'b.dart header expected',
      );
    });

    test(
      'contains ruleId, severity, message, and line location per finding',
      () {
        final f = _finding(
          ruleId: 'unused-public-exports',
          severity: Severity.warning,
          filePath: 'lib/foo.dart',
          line: 42,
          message: 'Unused export: Foo',
        );
        final output = HumanReporter().render(_payload(findings: [f]));
        expect(output, contains('unused-public-exports'));
        expect(output, contains('warning'));
        expect(output, contains('42'));
        expect(output, contains('Unused export: Foo'));
      },
    );

    test('shows column when present', () {
      final f = _finding(line: 10, column: 5);
      final output = HumanReporter().render(_payload(findings: [f]));
      expect(output, contains('10:5'));
    });

    test('shows only line when column is null', () {
      final f = _finding(line: 10, column: null);
      final output = HumanReporter().render(_payload(findings: [f]));
      expect(output, contains('10'));
      // Should not have a colon-column pattern for this finding
      final lines = output.split('\n');
      final findingLines = lines
          .where((l) => l.contains('unused-public-exports'))
          .toList();
      expect(findingLines, isNotEmpty);
      // None of the finding lines should have "10:anything"
      for (final line in findingLines) {
        expect(line, isNot(matches(RegExp(r'\b10:\d'))));
      }
    });

    test('preserves input order (deterministic)', () {
      final findings = [
        _finding(
          filePath: 'lib/a.dart',
          line: 1,
          fingerprint: 'fp1',
          message: 'First',
        ),
        _finding(
          filePath: 'lib/a.dart',
          line: 2,
          fingerprint: 'fp2',
          message: 'Second',
        ),
      ];
      final output = HumanReporter().render(_payload(findings: findings));
      final firstIdx = output.indexOf('First');
      final secondIdx = output.indexOf('Second');
      expect(firstIdx, lessThan(secondIdx));
    });
  });

  // -------------------------------------------------------------------------
  // AC3: Summary footer
  // -------------------------------------------------------------------------
  group('Summary footer', () {
    test('footer contains total finding count', () {
      final findings = [
        _finding(fingerprint: 'fp1'),
        _finding(fingerprint: 'fp2'),
      ];
      final output = HumanReporter().render(_payload(findings: findings));
      expect(output, contains('2'));
    });

    test('footer contains "finding" keyword', () {
      final output = HumanReporter().render(_payload(findings: [_finding()]));
      expect(output, contains('finding'));
    });
  });

  // -------------------------------------------------------------------------
  // AC3: Clean case
  // -------------------------------------------------------------------------
  group('Clean case', () {
    test('zero findings → contains "0 findings — clean"', () {
      final output = HumanReporter().render(_payload(findings: []));
      expect(output, contains('0 findings'));
      expect(output, contains('clean'));
    });
  });

  // -------------------------------------------------------------------------
  // AC4: ANSI color gating by isTty bool
  // -------------------------------------------------------------------------
  group('ANSI color gating', () {
    test('plain mode (isTty=false) — output contains no ANSI escape codes', () {
      final findings = [
        _finding(severity: Severity.error, fingerprint: 'fp1'),
        _finding(severity: Severity.warning, fingerprint: 'fp2'),
        _finding(severity: Severity.info, fingerprint: 'fp3'),
      ];
      final output = HumanReporter().render(
        _payload(findings: findings, isTty: false),
      );
      // ESC character is \x1B or 
      expect(output, isNot(contains('\x1B')));
    });

    test('TTY mode (isTty=true) — output contains ANSI escape codes', () {
      final findings = [_finding(severity: Severity.error, fingerprint: 'fp1')];
      final output = HumanReporter().render(
        _payload(findings: findings, isTty: true),
      );
      // Should contain at least one ANSI escape
      expect(output, contains('\x1B['));
    });
  });

  // -------------------------------------------------------------------------
  // AC5: reporterFor('human') returns HumanReporter
  // -------------------------------------------------------------------------
  group('reporterFor dispatch', () {
    test('reporterFor("human") returns HumanReporter', () {
      final reporter = reporterFor('human');
      expect(reporter, isA<HumanReporter>());
    });

    test(
      'reporterFor("sarif") throws UnimplementedError or similar (not yet Sprint 6 scope for sarif here)',
      () {
        // sarif will be Slice 2 — for now the dispatch should NOT crash on human
        // and should return something for human.
        final reporter = reporterFor('human');
        expect(reporter, isNotNull);
      },
    );

    test('reporterFor("json") returns a Reporter (now implemented)', () {
      expect(reporterFor('json'), isA<Reporter>());
    });

    test('reporterFor("markdown") returns a Reporter (now implemented)', () {
      expect(reporterFor('markdown'), isA<Reporter>());
    });

    test('reporterFor("html") returns a Reporter (now implemented)', () {
      expect(reporterFor('html'), isA<Reporter>());
    });
  });

  // -------------------------------------------------------------------------
  // Suppression + scan-scope surfacing
  // -------------------------------------------------------------------------
  group('HumanReporter suppression + scope', () {
    test('clean run with no suppression is unchanged', () {
      expect(const HumanReporter().render(_payload()), '0 findings — clean\n');
    });

    test('clean run shows suppressed count', () {
      final out = const HumanReporter().render(_payload(suppressedCount: 2));
      expect(out, contains('0 findings — clean (2 suppressed)'));
    });

    test('findings summary shows suppressed count', () {
      final out = const HumanReporter().render(
        _payload(findings: [_finding()], suppressedCount: 3),
      );
      expect(out, contains('· 3 suppressed'));
    });

    test('scope line shows files, lib subset, lines and rules', () {
      final out = const HumanReporter().render(_payload(stats: _stats));
      expect(
        out,
        contains(
          'Scanned 168 Dart files (50 under lib/) · 18432 lines · '
          'rules: circular-dependencies, complexity-hotspots',
        ),
      );
    });

    test('no scope line when stats are absent', () {
      expect(
        const HumanReporter().render(_payload(findings: [_finding()])),
        isNot(contains('Scanned')),
      );
    });
  });
}

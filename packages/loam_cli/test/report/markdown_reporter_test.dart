@TestOn('vm')
library;

import 'package:loam/src/model/finding.dart';
import 'package:loam/src/report/markdown_reporter.dart';
import 'package:loam/src/report/reporter.dart';
import 'package:loam/src/report/reporter_dispatch.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Shared fixture helpers (pattern from json_reporter_test.dart)
// ---------------------------------------------------------------------------

Finding _finding({
  String ruleId = 'unused-public-exports',
  Severity severity = Severity.warning,
  String filePath = '/project/lib/src/foo.dart',
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

void main() {
  // -------------------------------------------------------------------------
  // AC1: MarkdownReporter implements Reporter; render is a pure function
  // -------------------------------------------------------------------------
  group('MarkdownReporter interface', () {
    test('MarkdownReporter implements Reporter', () {
      final Reporter reporter = const MarkdownReporter();
      expect(reporter, isA<Reporter>());
    });
  });

  // -------------------------------------------------------------------------
  // AC2: Findings grouped by filePath with preserved input order
  // -------------------------------------------------------------------------
  group('Grouping and ordering', () {
    test('findings grouped by filePath — one heading per file', () {
      final findings = [
        _finding(
          filePath: '/project/lib/src/foo.dart',
          fingerprint: 'fp1',
          line: 10,
        ),
        _finding(
          filePath: '/project/lib/src/bar.dart',
          fingerprint: 'fp2',
          line: 5,
        ),
        _finding(
          filePath: '/project/lib/src/foo.dart',
          fingerprint: 'fp3',
          line: 20,
        ),
      ];
      final output = const MarkdownReporter().render(
        _payload(findings: findings),
      );

      // Each file heading appears exactly once.
      final fooHeadings = RegExp(
        r'### lib/src/foo\.dart',
      ).allMatches(output).length;
      final barHeadings = RegExp(
        r'### lib/src/bar\.dart',
      ).allMatches(output).length;
      expect(fooHeadings, equals(1));
      expect(barHeadings, equals(1));
    });

    test('foo.dart appears before bar.dart when foo is first in input', () {
      final findings = [
        _finding(
          filePath: '/project/lib/src/foo.dart',
          fingerprint: 'fp1',
          line: 10,
        ),
        _finding(
          filePath: '/project/lib/src/bar.dart',
          fingerprint: 'fp2',
          line: 5,
        ),
      ];
      final output = const MarkdownReporter().render(
        _payload(findings: findings),
      );

      final fooPos = output.indexOf('### lib/src/foo.dart');
      final barPos = output.indexOf('### lib/src/bar.dart');
      expect(fooPos, lessThan(barPos));
    });
  });

  // -------------------------------------------------------------------------
  // AC3: GFM table with correct columns
  // -------------------------------------------------------------------------
  group('Table structure', () {
    test('output contains GFM table header row', () {
      final output = const MarkdownReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(output, contains('| Line | Severity | Rule | Message |'));
    });

    test('output contains GFM table separator row', () {
      final output = const MarkdownReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(output, contains('|------|----------|------|---------|'));
    });

    test('finding row contains line number', () {
      final f = _finding(line: 42);
      final output = const MarkdownReporter().render(_payload(findings: [f]));
      expect(output, contains('| 42 |'));
    });

    test('finding row contains severity', () {
      final f = _finding(severity: Severity.error, fingerprint: 'e1');
      final output = const MarkdownReporter().render(_payload(findings: [f]));
      expect(output, contains('| error |'));
    });

    test('finding row contains ruleId', () {
      final f = _finding(ruleId: 'some-rule');
      final output = const MarkdownReporter().render(_payload(findings: [f]));
      expect(output, contains('| some-rule |'));
    });

    test('finding row contains message', () {
      final f = _finding(message: 'Some message text');
      final output = const MarkdownReporter().render(_payload(findings: [f]));
      expect(output, contains('Some message text'));
    });
  });

  // -------------------------------------------------------------------------
  // AC4: Pipe escaping in message cells
  // -------------------------------------------------------------------------
  group('Pipe escaping', () {
    test('pipe character in message is escaped as \\|', () {
      final f = _finding(message: 'foo | bar');
      final output = const MarkdownReporter().render(_payload(findings: [f]));
      expect(output, contains(r'foo \| bar'));
      expect(output, isNot(contains('foo | bar | ')));
    });

    test('multiple pipes in message are all escaped', () {
      final f = _finding(message: 'a | b | c');
      final output = const MarkdownReporter().render(_payload(findings: [f]));
      expect(output, contains(r'a \| b \| c'));
    });
  });

  // -------------------------------------------------------------------------
  // AC5: Summary line with total, severity breakdown, tool+ruleset metadata
  // -------------------------------------------------------------------------
  group('Summary line', () {
    test('summary includes total count', () {
      final findings = [
        _finding(fingerprint: 'fp1'),
        _finding(fingerprint: 'fp2'),
      ];
      final output = const MarkdownReporter().render(
        _payload(findings: findings),
      );
      expect(output, contains('2 findings'));
    });

    test('summary uses singular "finding" for exactly 1', () {
      final output = const MarkdownReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(output, contains('1 finding'));
      expect(output, isNot(contains('1 findings')));
    });

    test('summary includes severity breakdown in parentheses', () {
      final findings = [
        _finding(severity: Severity.error, fingerprint: 'fp1'),
        _finding(severity: Severity.warning, fingerprint: 'fp2'),
      ];
      final output = const MarkdownReporter().render(
        _payload(findings: findings),
      );
      // Severity.values order: info, warning, error — so warning appears before error.
      expect(output, contains('(warning: 1, error: 1)'));
    });

    test('summary includes toolVersion', () {
      final output = const MarkdownReporter().render(
        _payload(findings: [_finding()], toolVersion: '1.2.3'),
      );
      expect(output, contains('loam 1.2.3'));
    });

    test('summary includes rulesetVersion', () {
      final output = const MarkdownReporter().render(
        _payload(findings: [_finding()], rulesetVersion: 'ruleset@deadbeef'),
      );
      expect(output, contains('ruleset@deadbeef'));
    });

    test('summary uses dot-separator between tool and ruleset', () {
      final output = const MarkdownReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(output, contains('·'));
    });
  });

  // -------------------------------------------------------------------------
  // AC6: Relative + forward-slash paths; no absolute paths or timestamps
  // -------------------------------------------------------------------------
  group('Path normalisation', () {
    test('filePath heading is relative to projectRoot', () {
      final f = _finding(filePath: '/project/lib/src/foo.dart');
      final output = const MarkdownReporter().render(
        _payload(findings: [f], projectRoot: '/project'),
      );
      expect(output, contains('### lib/src/foo.dart'));
    });

    test('filePath uses forward slashes', () {
      final f = _finding(filePath: '/project/lib/src/foo.dart');
      final output = const MarkdownReporter().render(
        _payload(findings: [f], projectRoot: '/project'),
      );
      expect(output, isNot(contains('\\')));
    });

    test('output contains no absolute project root path', () {
      final f = _finding(filePath: '/secret/project/lib/src/foo.dart');
      final output = const MarkdownReporter().render(
        _payload(findings: [f], projectRoot: '/secret/project'),
      );
      expect(output, isNot(contains('/secret/project')));
    });

    test('output contains no ISO 8601 timestamp patterns', () {
      final output = const MarkdownReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(output, isNot(matches(RegExp(r'\d{4}-\d{2}-\d{2}T'))));
    });
  });

  // -------------------------------------------------------------------------
  // AC7: Empty run — "0 findings — clean" (no empty table)
  // -------------------------------------------------------------------------
  group('Empty findings', () {
    test('empty run returns "0 findings — clean" line', () {
      final output = const MarkdownReporter().render(_payload(findings: []));
      expect(output, equals('0 findings — clean\n'));
    });

    test('empty run does not produce a table', () {
      final output = const MarkdownReporter().render(_payload(findings: []));
      expect(output, isNot(contains('| Line |')));
    });
  });

  // -------------------------------------------------------------------------
  // AC8: Byte-identical reproducibility
  // -------------------------------------------------------------------------
  group('Reproducibility', () {
    test('render twice with same payload produces identical string', () {
      final reporter = const MarkdownReporter();
      final payload = _payload(findings: [_finding()]);
      expect(reporter.render(payload), equals(reporter.render(payload)));
    });

    test('render twice with multi-file payload produces identical string', () {
      final reporter = const MarkdownReporter();
      final findings = [
        _finding(
          filePath: '/project/lib/src/foo.dart',
          fingerprint: 'fp1',
          line: 10,
        ),
        _finding(
          filePath: '/project/lib/src/bar.dart',
          fingerprint: 'fp2',
          line: 5,
        ),
      ];
      final payload = _payload(findings: findings);
      expect(reporter.render(payload), equals(reporter.render(payload)));
    });
  });

  // -------------------------------------------------------------------------
  // AC9: reporterFor('markdown') dispatch
  // -------------------------------------------------------------------------
  group('reporterFor dispatch', () {
    test('reporterFor("markdown") returns MarkdownReporter', () {
      final reporter = reporterFor('markdown');
      expect(reporter, isA<MarkdownReporter>());
    });

    test('reporterFor("markdown") does not throw', () {
      expect(() => reporterFor('markdown'), returnsNormally);
    });
  });

  group('MarkdownReporter suppression + scope', () {
    test('clean run with no suppression is unchanged', () {
      expect(
        const MarkdownReporter().render(_payload()),
        '0 findings — clean\n',
      );
    });

    test('clean run shows suppressed count', () {
      expect(
        const MarkdownReporter().render(_payload(suppressedCount: 2)),
        contains('0 findings — clean (2 suppressed)'),
      );
    });

    test('scope line is rendered as italic text', () {
      final out = const MarkdownReporter().render(
        _payload(
          stats: const ScanStats(
            filesAnalyzed: 168,
            libFilesAnalyzed: 50,
            linesAnalyzed: 18432,
            rulesRun: ['complexity-hotspots'],
          ),
        ),
      );
      expect(
        out,
        contains(
          '_Scanned 168 Dart files (50 under lib/) · 18432 lines · '
          'rules: complexity-hotspots._',
        ),
      );
    });
  });
}

@TestOn('vm')
library;

import 'package:loam/src/model/finding.dart';
import 'package:loam/src/report/html_reporter.dart';
import 'package:loam/src/report/reporter.dart';
import 'package:loam/src/report/reporter_dispatch.dart';
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Shared fixture helpers (mirrors json_reporter_test.dart pattern)
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
}) => ReportPayload(
  findings: findings,
  projectRoot: projectRoot,
  rulesetVersion: rulesetVersion,
  toolVersion: toolVersion,
  isTty: isTty,
);

void main() {
  // -------------------------------------------------------------------------
  // AC1: HtmlReporter implements Reporter; pure function (no I/O)
  // -------------------------------------------------------------------------
  group('HtmlReporter interface', () {
    test('HtmlReporter implements Reporter', () {
      final Reporter reporter = const HtmlReporter();
      expect(reporter, isA<Reporter>());
    });

    test('render returns a non-empty String', () {
      final output = const HtmlReporter().render(_payload());
      expect(output, isNotEmpty);
    });
  });

  // -------------------------------------------------------------------------
  // AC2: Self-contained — no external http/https/CDN references
  // -------------------------------------------------------------------------
  group('Self-contained (no external resources)', () {
    test('output contains no http:// links', () {
      final output = const HtmlReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(
        output,
        isNot(matches(RegExp(r'http://'))),
        reason: 'HTML must not contain http:// external resource links',
      );
    });

    test('output contains no https:// links', () {
      final output = const HtmlReporter().render(
        _payload(findings: [_finding()]),
      );
      // The only permitted https:// would be in the data payload itself (message
      // text), not in HTML structure. We check the structural parts (src/href).
      final srcHref = RegExp(
        r'(src|href)\s*=\s*"https?://[^"]+"',
        caseSensitive: false,
      );
      expect(
        output,
        isNot(matches(srcHref)),
        reason: 'HTML must not load external resources via src/href',
      );
    });

    test('output contains no <link rel="stylesheet"> external reference', () {
      final output = const HtmlReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(
        output,
        isNot(
          matches(
            RegExp(r'<link[^>]+stylesheet[^>]+https?://', caseSensitive: false),
          ),
        ),
      );
    });

    test('output contains no <script src="..."> with external URL', () {
      final output = const HtmlReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(
        output,
        isNot(
          matches(
            RegExp(r'<script[^>]+src\s*=\s*"https?://', caseSensitive: false),
          ),
        ),
      );
    });

    test(
      'output has no CDN references (cdnjs, unpkg, jsdelivr, fonts.google)',
      () {
        final output = const HtmlReporter().render(
          _payload(findings: [_finding()]),
        );
        expect(output, isNot(contains('cdnjs')));
        expect(output, isNot(contains('unpkg.com')));
        expect(output, isNot(contains('jsdelivr')));
        expect(output, isNot(contains('fonts.googleapis')));
        expect(output, isNot(contains('fonts.gstatic')));
      },
    );

    test('output is a complete HTML document', () {
      final output = const HtmlReporter().render(_payload());
      expect(output, contains('<!DOCTYPE html>'));
      expect(output, contains('<html'));
      expect(output, contains('</html>'));
    });
  });

  // -------------------------------------------------------------------------
  // AC3: All findings embedded as structured data; browsable by rule/severity/file
  // -------------------------------------------------------------------------
  group('Findings embedded and browsable', () {
    test('output contains embedded JSON data block', () {
      final output = const HtmlReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(output, contains('application/json'));
    });

    test('all findings are present in the output', () {
      final findings = [
        _finding(ruleId: 'rule-a', fingerprint: 'fp1', message: 'Msg A'),
        _finding(ruleId: 'rule-b', fingerprint: 'fp2', message: 'Msg B'),
        _finding(ruleId: 'rule-c', fingerprint: 'fp3', message: 'Msg C'),
      ];
      final output = const HtmlReporter().render(_payload(findings: findings));
      expect(output, contains('rule-a'));
      expect(output, contains('rule-b'));
      expect(output, contains('rule-c'));
      expect(output, contains('Msg A'));
      expect(output, contains('Msg B'));
      expect(output, contains('Msg C'));
    });

    test('finding file:line code-context is present', () {
      final f = _finding(filePath: '/project/lib/src/foo.dart', line: 42);
      final output = const HtmlReporter().render(
        _payload(findings: [f], projectRoot: '/project'),
      );
      // Relative path + line number must appear in output
      expect(output, contains('lib/src/foo.dart'));
      expect(output, contains('42'));
    });

    test('severity values appear in output', () {
      final findings = [
        _finding(severity: Severity.error, fingerprint: 'fp1'),
        _finding(severity: Severity.warning, fingerprint: 'fp2'),
        _finding(severity: Severity.info, fingerprint: 'fp3'),
      ];
      final output = const HtmlReporter().render(_payload(findings: findings));
      expect(output, contains('error'));
      expect(output, contains('warning'));
      expect(output, contains('info'));
    });

    test('output contains group-by controls (rule, severity, file)', () {
      final output = const HtmlReporter().render(
        _payload(findings: [_finding()]),
      );
      // The select options for grouping must be present
      expect(output, contains('Rule'));
      expect(output, contains('Severity'));
      expect(output, contains('File'));
    });

    test(
      'embedded JSON contains ruleId, severity, filePath, line, message, fingerprint',
      () {
        final f = _finding(
          ruleId: 'my-rule',
          severity: Severity.error,
          filePath: '/project/lib/src/bar.dart',
          line: 5,
          column: 3,
          message: 'Something wrong',
          fingerprint: 'deadbeef',
        );
        final output = const HtmlReporter().render(
          _payload(findings: [f], projectRoot: '/project'),
        );
        expect(output, contains('"ruleId"'));
        expect(output, contains('"my-rule"'));
        expect(output, contains('"severity"'));
        expect(output, contains('"error"'));
        expect(output, contains('"filePath"'));
        expect(output, contains('"line"'));
        expect(output, contains('"message"'));
        expect(output, contains('"Something wrong"'));
        expect(output, contains('"fingerprint"'));
        expect(output, contains('"deadbeef"'));
      },
    );
  });

  // -------------------------------------------------------------------------
  // AC4: Byte-identical reproducibility
  // -------------------------------------------------------------------------
  group('Reproducibility (Invariant 5)', () {
    test('render twice with same payload produces identical string', () {
      final reporter = const HtmlReporter();
      final payload = _payload(findings: [_finding()]);
      expect(reporter.render(payload), equals(reporter.render(payload)));
    });

    test('render with multiple findings is byte-identical on two runs', () {
      final reporter = const HtmlReporter();
      final findings = [
        _finding(ruleId: 'r1', fingerprint: 'fp1'),
        _finding(ruleId: 'r2', fingerprint: 'fp2'),
        _finding(ruleId: 'r3', severity: Severity.error, fingerprint: 'fp3'),
      ];
      final payload = _payload(findings: findings);
      expect(reporter.render(payload), equals(reporter.render(payload)));
    });

    test('output contains no ISO 8601 timestamp patterns', () {
      final output = const HtmlReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(output, isNot(matches(RegExp(r'\d{4}-\d{2}-\d{2}T'))));
    });

    test('output contains no absolute project root path', () {
      final f = _finding(filePath: '/secret/project/lib/src/foo.dart');
      final output = const HtmlReporter().render(
        _payload(findings: [f], projectRoot: '/secret/project'),
      );
      expect(output, isNot(contains('/secret/project')));
    });
  });

  // -------------------------------------------------------------------------
  // AC5: reporterFor('html') dispatch returns HtmlReporter
  // -------------------------------------------------------------------------
  group('reporterFor dispatch', () {
    test('reporterFor("html") returns HtmlReporter', () {
      final reporter = reporterFor('html');
      expect(reporter, isA<HtmlReporter>());
    });

    test('reporterFor("html") does not throw', () {
      expect(() => reporterFor('html'), returnsNormally);
    });
  });

  // -------------------------------------------------------------------------
  // AC6: Empty findings run produces plausible page
  // -------------------------------------------------------------------------
  group('Empty findings', () {
    test('empty run: produces complete HTML document', () {
      final output = const HtmlReporter().render(_payload(findings: []));
      expect(output, contains('<!DOCTYPE html>'));
      expect(output, contains('<html'));
      expect(output, contains('</html>'));
    });

    test('empty run: summary shows 0 findings', () {
      final output = const HtmlReporter().render(_payload(findings: []));
      expect(output, contains('0 finding'));
    });

    test('empty run: still embeds JSON data block', () {
      final output = const HtmlReporter().render(_payload(findings: []));
      expect(output, contains('application/json'));
    });
  });

  // -------------------------------------------------------------------------
  // Anti-vocabulary: must not use "Dashboard" or "GUI" in output
  // -------------------------------------------------------------------------
  group('Anti-vocabulary (CONTEXT.md)', () {
    test('output does not contain "Dashboard"', () {
      final output = const HtmlReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(output, isNot(contains('Dashboard')));
    });

    test('output does not contain "GUI"', () {
      final output = const HtmlReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(output, isNot(contains('GUI')));
    });
  });

  // -------------------------------------------------------------------------
  // Path normalisation: file paths are relative and forward-slash-normalised
  // -------------------------------------------------------------------------
  group('Path normalisation', () {
    test('filePath in output is relative, not absolute', () {
      final f = _finding(filePath: '/project/lib/src/foo.dart');
      final output = const HtmlReporter().render(
        _payload(findings: [f], projectRoot: '/project'),
      );
      expect(output, contains('lib/src/foo.dart'));
      expect(output, isNot(contains('"/project/lib')));
    });

    test('filePath has no leading slash in embedded JSON', () {
      final f = _finding(filePath: '/project/lib/src/foo.dart');
      final output = const HtmlReporter().render(
        _payload(findings: [f], projectRoot: '/project'),
      );
      // filePath value in JSON should not start with /
      expect(output, isNot(contains('"/project/')));
      // should contain the relative path
      expect(output, contains('"lib/src/foo.dart"'));
    });
  });
}

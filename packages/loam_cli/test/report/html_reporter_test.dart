@TestOn('vm')
library;

import 'package:loam/src/model/finding.dart';
import 'package:loam/src/report/fix_prompt_template.dart';
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

    test('output loads no external resources via src or <link href>', () {
      final output = const HtmlReporter().render(
        _payload(findings: [_finding()]),
      );
      // Navigation anchors (<a href="https://...">) to the website / repo /
      // sponsor are allowed — they don't make the report depend on the network
      // to *render*. Only resource loading is forbidden: script/img/iframe
      // src and external stylesheet <link href>.
      final externalSrc = RegExp(r'src\s*=\s*"https?://', caseSensitive: false);
      final externalLink = RegExp(
        r'<link[^>]+href\s*=\s*"https?://',
        caseSensitive: false,
      );
      expect(
        output,
        isNot(matches(externalSrc)),
        reason: 'HTML must not load external resources via src=',
      );
      expect(
        output,
        isNot(matches(externalLink)),
        reason: 'HTML must not load an external stylesheet via <link href>',
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
  // Marketing & rule-reference links (self-contained: navigation only)
  // -------------------------------------------------------------------------
  group('Marketing & rule-reference links', () {
    test('footer links to the website, the repo and the sponsor page', () {
      final output = const HtmlReporter().render(_payload());
      expect(output, contains('href="https://getloam.dev"'));
      expect(output, contains('href="https://github.com/silvio-l/loam"'));
      expect(output, contains('href="https://github.com/sponsors/silvio-l"'));
    });

    test('masthead brand links to the website', () {
      final output = const HtmlReporter().render(_payload());
      expect(output, contains('class="brand" href="https://getloam.dev"'));
    });

    test('masthead shows a sponsor link, not only the footer', () {
      final output = const HtmlReporter().render(_payload());
      expect(output, contains('class="sponsor-link"'));
      // Sponsor URL appears in both the masthead pill and the footer.
      final hits = 'https://github.com/sponsors/silvio-l'
          .allMatches(output)
          .length;
      expect(hits, greaterThanOrEqualTo(2));
    });

    test('finding rule ids deep-link to the rule reference on the website', () {
      final output = const HtmlReporter().render(
        _payload(findings: [_finding()]),
      );
      // The per-finding link is assembled in JS; the base URL is embedded.
      expect(output, contains('https://getloam.dev/rules#'));
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

  // -------------------------------------------------------------------------
  // Issue 07 — AC1: Findings are individually selectable (checkboxes)
  // -------------------------------------------------------------------------
  group('Issue 07 — AC1: per-finding selection checkboxes', () {
    test('output contains checkbox inputs for findings', () {
      final output = const HtmlReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(
        output,
        contains('type="checkbox"'),
        reason: 'each finding must have a checkbox',
      );
    });

    test('checkbox has class "finding-check"', () {
      final output = const HtmlReporter().render(
        _payload(findings: [_finding()]),
      );
      expect(output, contains('class="finding-check"'));
    });

    test('select-all button is present', () {
      final output = const HtmlReporter().render(_payload());
      expect(output, contains('selectAllBtn'));
    });

    test('clear-selection button is present', () {
      final output = const HtmlReporter().render(_payload());
      expect(output, contains('clearSelBtn'));
    });
  });

  // -------------------------------------------------------------------------
  // Issue 07 — AC2: FixPromptTemplate embedded with prompt@ver marker
  // -------------------------------------------------------------------------
  group('Issue 07 — AC2: FixPromptTemplate embedded', () {
    test('output contains the fix-prompt template script block', () {
      final output = const HtmlReporter().render(_payload());
      expect(
        output,
        contains('text/x-loam-template'),
        reason: 'Fix-Prompt template must be embedded as a script block',
      );
    });

    test('output contains the prompt@ver marker from kPromptVersion', () {
      final output = const HtmlReporter().render(_payload());
      expect(
        output,
        contains(kPromptVersion),
        reason: 'prompt@ver marker must appear in the embedded HTML',
      );
    });

    test('output contains the {{FINDINGS}} placeholder in the template', () {
      final output = const HtmlReporter().render(_payload());
      expect(
        output,
        contains('{{FINDINGS}}'),
        reason:
            'template placeholder {{FINDINGS}} must be embedded for JS to fill',
      );
    });

    test('output contains the loam-fix-hints JSON block', () {
      final output = const HtmlReporter().render(_payload());
      expect(
        output,
        contains('loam-fix-hints'),
        reason: 'fix-hints map must be embedded so JS can look up hints',
      );
    });

    test('fix-hints JSON block contains __generic__ key', () {
      final output = const HtmlReporter().render(_payload());
      expect(output, contains('__generic__'));
    });

    test('fix-hints JSON block contains unused-public-exports key', () {
      final output = const HtmlReporter().render(_payload());
      expect(output, contains('unused-public-exports'));
    });
  });

  // -------------------------------------------------------------------------
  // Issue 07 — AC5: Copy-to-Clipboard button present
  // -------------------------------------------------------------------------
  group('Issue 07 — AC5: Copy-to-Clipboard button', () {
    test('output contains copyPromptBtn element', () {
      final output = const HtmlReporter().render(_payload());
      expect(
        output,
        contains('copyPromptBtn'),
        reason: 'copy-to-clipboard button must be present',
      );
    });

    test('output contains fix-prompt-output textarea', () {
      final output = const HtmlReporter().render(_payload());
      expect(
        output,
        contains('fix-prompt-output'),
        reason: 'prompt output textarea must be present',
      );
    });

    test('output contains fix-prompt-section', () {
      final output = const HtmlReporter().render(_payload());
      expect(output, contains('fix-prompt-section'));
    });
  });

  // -------------------------------------------------------------------------
  // Issue 07 — AC6: Pure renderer — no logic/thresholds/LLM in report
  // -------------------------------------------------------------------------
  group('Issue 07 — AC6: Pure renderer (Invariante 4)', () {
    test('JS does not reference LLM or fetch', () {
      final output = const HtmlReporter().render(_payload());
      // No fetch() calls, no XMLHttpRequest, no WebSocket
      expect(output, isNot(contains('fetch(')));
      expect(output, isNot(contains('XMLHttpRequest')));
      expect(output, isNot(contains('WebSocket')));
    });

    test('output has no server-side template markers', () {
      final output = const HtmlReporter().render(_payload());
      // No PHP-style, Jinja, or other server-side markers
      expect(output, isNot(contains('<?php')));
      expect(output, isNot(contains('{%')));
    });
  });

  // -------------------------------------------------------------------------
  // Issue 07 — Reproducibility of extended output (Invariante 5)
  // -------------------------------------------------------------------------
  group('Issue 07 — Reproducibility with selection UI (Invariante 5)', () {
    test(
      'render with findings is byte-identical on two runs (with new UI)',
      () {
        final reporter = const HtmlReporter();
        final findings = [
          _finding(ruleId: 'unused-public-exports', fingerprint: 'fp1'),
          _finding(
            ruleId: 'unused-public-exports',
            fingerprint: 'fp2',
            filePath: '/project/lib/src/bar.dart',
          ),
        ];
        final payload = _payload(findings: findings);
        expect(reporter.render(payload), equals(reporter.render(payload)));
      },
    );
  });
}

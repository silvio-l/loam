@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// CLI integration test: `loam scan --format html` end-to-end via subprocess
/// against `test/fixtures/unused_exports_fixture`.
///
/// HTML is a self-contained, viewable document: the CLI writes it to a file
/// (default `loam-report.html`, override with `--output`) and — only when run
/// interactively — opens it in the browser. The subprocess here is non-TTY, so
/// no browser is launched; stdout carries a one-line confirmation and the HTML
/// lives in the output file. These tests therefore assert on the file content,
/// not on stdout.
void main() {
  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'unused_exports_fixture',
    ),
  );

  final entrypoint = p.join(Directory.current.path, 'bin', 'loam.dart');

  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('loam_html_cli_test');
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Runs `loam --format html --output <outPath> scan -p <fixture>`.
  ProcessResult runHtml(String outPath) {
    return Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'html',
      '--output',
      outPath,
      'scan',
      '--project-root',
      fixturePath,
    ]);
  }

  /// Runs the report and returns the written HTML file content.
  String reportContent() {
    final out = p.join(tmp.path, 'report.html');
    final result = runHtml(out);
    expect(
      result.exitCode,
      equals(1),
      reason: 'should exit 1 when findings are present',
    );
    return File(out).readAsStringSync();
  }

  // -------------------------------------------------------------------------
  // Exit code & streams
  // -------------------------------------------------------------------------

  test('loam scan --format html: exit 1 for fixture with findings', () {
    final out = p.join(tmp.path, 'report.html');
    expect(
      runHtml(out).exitCode,
      equals(1),
      reason:
          'should exit 1 when findings are present (reporter does not affect exit code)',
    );
  });

  test('loam scan --format html: stderr is empty on success', () {
    final out = p.join(tmp.path, 'report.html');
    final err = runHtml(out).stderr as String;
    expect(err.trim(), isEmpty, reason: 'no error output expected');
  });

  test(
    'loam scan --format html: stdout reports the file path and contains no raw HTML',
    () {
      final out = p.join(tmp.path, 'report.html');
      final stdoutStr = runHtml(out).stdout as String;
      expect(
        stdoutStr,
        contains(out),
        reason: 'stdout must tell the user where the report was written',
      );
      expect(
        stdoutStr,
        isNot(contains('<!DOCTYPE html>')),
        reason: 'the HTML document goes to the file, not to stdout',
      );
    },
  );

  // -------------------------------------------------------------------------
  // Output file location
  // -------------------------------------------------------------------------

  test(
    'loam scan --format html: writes loam-report.html into the working directory by default',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'html',
        'scan',
        '--project-root',
        fixturePath,
      ], workingDirectory: tmp.path);
      expect(result.exitCode, equals(1));
      final defaultFile = File(p.join(tmp.path, 'loam-report.html'));
      expect(
        defaultFile.existsSync(),
        isTrue,
        reason: 'default report file must be loam-report.html in the CWD',
      );
      expect(defaultFile.readAsStringSync(), contains('<!DOCTYPE html>'));
    },
  );

  test('loam scan --format html: --output writes to the given path', () {
    final out = p.join(tmp.path, 'nested', 'custom-name.html');
    Directory(p.dirname(out)).createSync(recursive: true);
    final result = runHtml(out);
    expect(result.exitCode, equals(1));
    expect(File(out).existsSync(), isTrue);
    expect(File(out).readAsStringSync(), contains('<!DOCTYPE html>'));
  });

  // -------------------------------------------------------------------------
  // HTML document content (read from the output file)
  // -------------------------------------------------------------------------

  test('loam scan --format html: output file is a complete HTML document', () {
    final html = reportContent();
    expect(
      html,
      contains('<!DOCTYPE html>'),
      reason: 'output must be an HTML document',
    );
    expect(html, contains('<html'), reason: 'output must open an html element');
    expect(
      html,
      contains('</html>'),
      reason: 'output must close the html element',
    );
  });

  test('loam scan --format html: output file contains embedded JSON data', () {
    expect(
      reportContent(),
      contains('application/json'),
      reason: 'output must embed findings as JSON',
    );
  });

  test(
    'loam scan --format html: findings reference unused-public-exports rule',
    () {
      expect(
        reportContent(),
        contains('unused-public-exports'),
        reason: 'HTML output must reference the unused-public-exports rule',
      );
    },
  );

  test('loam scan --format html: output file loads no external resources', () {
    final html = reportContent();
    // Navigation anchors (website / repo / sponsor / rule reference) are
    // allowed; only resource loading is forbidden.
    expect(
      html,
      isNot(matches(RegExp(r'src\s*=\s*"https?://', caseSensitive: false))),
      reason: 'no external resource via src=',
    );
    expect(
      html,
      isNot(
        matches(
          RegExp(r'<link[^>]+href\s*=\s*"https?://', caseSensitive: false),
        ),
      ),
      reason: 'no external stylesheet <link>',
    );
    expect(html, isNot(contains('cdnjs')));
    expect(html, isNot(contains('fonts.googleapis')));
  });

  test(
    'loam scan --format html: filePaths are relative (no absolute paths in output)',
    () {
      expect(
        reportContent(),
        isNot(contains(fixturePath)),
        reason: 'absolute project root path must not appear in HTML content',
      );
    },
  );

  // -------------------------------------------------------------------------
  // Selection markup + template + clipboard button
  // -------------------------------------------------------------------------

  test(
    'loam scan --format html: output contains per-finding checkboxes (AC1)',
    () {
      final html = reportContent();
      expect(
        html,
        contains('type="checkbox"'),
        reason: 'HTML must contain per-finding selection checkboxes',
      );
      expect(
        html,
        contains('finding-check'),
        reason: 'checkboxes must use the finding-check class',
      );
    },
  );

  test(
    'loam scan --format html: output contains embedded Fix-Prompt template (AC2)',
    () {
      final html = reportContent();
      expect(
        html,
        contains('text/x-loam-template'),
        reason: 'HTML must contain the Fix-Prompt template script block',
      );
      expect(
        html,
        contains('prompt@v'),
        reason: 'embedded template must carry the prompt@ver marker',
      );
      expect(
        html,
        contains('{{FINDINGS}}'),
        reason: 'template placeholder must be present for JS assembly',
      );
    },
  );

  test(
    'loam scan --format html: output contains Copy-to-Clipboard button (AC5)',
    () {
      expect(
        reportContent(),
        contains('copyPromptBtn'),
        reason: 'HTML must contain the copy-to-clipboard button',
      );
    },
  );
}

@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// CLI integration test: `loam scan --format html` end-to-end via subprocess
/// against `test/fixtures/unused_exports_fixture`.
///
/// Mirrors the approach in `test/report/markdown_reporter_cli_test.dart`:
/// a real subprocess is forked so stdout is captured cleanly (no TTY).
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

  // -------------------------------------------------------------------------
  // loam scan --format html: end-to-end
  // -------------------------------------------------------------------------

  test('loam scan --format html: exit 1 for fixture with findings', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'html',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    expect(
      result.exitCode,
      equals(1),
      reason:
          'should exit 1 when findings are present (reporter does not affect exit code)',
    );
  });

  test('loam scan --format html: stdout is a complete HTML document', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'html',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    final out = result.stdout as String;
    expect(
      out,
      contains('<!DOCTYPE html>'),
      reason: 'output must be an HTML document',
    );
    expect(out, contains('<html'), reason: 'output must open an html element');
    expect(
      out,
      contains('</html>'),
      reason: 'output must close the html element',
    );
  });

  test('loam scan --format html: stdout contains embedded JSON data', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'html',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    final out = result.stdout as String;
    expect(
      out,
      contains('application/json'),
      reason: 'output must embed findings as JSON',
    );
  });

  test(
    'loam scan --format html: findings reference unused-public-exports rule',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'html',
        'scan',
        '--project-root',
        fixturePath,
      ]);
      final out = result.stdout as String;
      expect(
        out,
        contains('unused-public-exports'),
        reason: 'HTML output must reference the unused-public-exports rule',
      );
    },
  );

  test(
    'loam scan --format html: stdout has no external resource references',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'html',
        'scan',
        '--project-root',
        fixturePath,
      ]);
      final out = result.stdout as String;
      // No CDN or external src/href
      expect(
        out,
        isNot(
          matches(RegExp(r'(src|href)\s*=\s*"https?://', caseSensitive: false)),
        ),
      );
      expect(out, isNot(contains('cdnjs')));
      expect(out, isNot(contains('fonts.googleapis')));
    },
  );

  test(
    'loam scan --format html: filePaths are relative (no absolute paths in output)',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'html',
        'scan',
        '--project-root',
        fixturePath,
      ]);
      final out = result.stdout as String;
      // The fixture path should not appear as an absolute path in the content.
      expect(
        out,
        isNot(contains(fixturePath)),
        reason: 'absolute project root path must not appear in HTML content',
      );
    },
  );

  test('loam scan --format html: stderr is empty on success', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'html',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    final err = result.stderr as String;
    expect(err.trim(), isEmpty, reason: 'no error output expected');
  });
}

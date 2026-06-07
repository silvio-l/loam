@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// CLI integration test: `loam scan --format markdown` end-to-end via subprocess
/// against `test/fixtures/unused_exports_fixture`.
///
/// Mirrors the approach in `test/report/json_reporter_cli_test.dart`:
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
  // loam scan --format markdown: end-to-end
  // -------------------------------------------------------------------------

  test('loam scan --format markdown: exit 1 for fixture with findings', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'markdown',
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

  test('loam scan --format markdown: stdout contains GFM table header', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'markdown',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    final out = result.stdout as String;
    expect(
      out,
      contains('| Line | Severity | Rule | Message |'),
      reason: 'output must include a GFM table header row',
    );
  });

  test('loam scan --format markdown: stdout contains file heading', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'markdown',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    final out = result.stdout as String;
    expect(
      out,
      matches(RegExp(r'### \S+')),
      reason: 'output must include at least one file heading (### ...)',
    );
  });

  test(
    'loam scan --format markdown: findings reference unused-public-exports rule',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'markdown',
        'scan',
        '--project-root',
        fixturePath,
      ]);
      final out = result.stdout as String;
      expect(
        out,
        contains('unused-public-exports'),
        reason: 'Markdown output must reference the unused-public-exports rule',
      );
    },
  );

  test(
    'loam scan --format markdown: output contains summary line with "findings"',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'markdown',
        'scan',
        '--project-root',
        fixturePath,
      ]);
      final out = result.stdout as String;
      expect(
        out,
        matches(RegExp(r'\d+ findings?')),
        reason: 'output must include a summary line with finding count',
      );
    },
  );

  test(
    'loam scan --format markdown: filePaths are relative (no absolute paths in output)',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'markdown',
        'scan',
        '--project-root',
        fixturePath,
      ]);
      final out = result.stdout as String;
      // The fixture path should not appear as an absolute path in the content.
      expect(
        out,
        isNot(contains(fixturePath)),
        reason:
            'absolute project root path must not appear in Markdown content',
      );
    },
  );
}

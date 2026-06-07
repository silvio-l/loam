@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// CLI integration test: `loam scan --format human` end-to-end via subprocess
/// against `test/fixtures/unused_exports_fixture`.
///
/// Mirrors the approach in `test/command/scan_command_test.dart`:
/// a real subprocess is forked so stdout is captured cleanly (no TTY,
/// so isTty=false → no ANSI escapes).
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

  // ---------------------------------------------------------------------------
  // AC6: loam scan --format human is grouped & contains ruleId
  // ---------------------------------------------------------------------------

  test('loam scan --format human: exit 1 for fixture with findings', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'human',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    expect(
      result.exitCode,
      equals(1),
      reason: 'should exit 1 when findings are present',
    );
  });

  test('loam scan --format human: output contains ruleId', () {
    final result = Process.runSync(Platform.executable, [
      'run',
      entrypoint,
      '--format',
      'human',
      'scan',
      '--project-root',
      fixturePath,
    ]);
    final out = result.stdout as String;
    expect(
      out,
      contains('unused-public-exports'),
      reason: 'human output must include the ruleId',
    );
  });

  test(
    'loam scan --format human: output is grouped by file (file header present)',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'human',
        'scan',
        '--project-root',
        fixturePath,
      ]);
      final out = result.stdout as String;
      // Grouped output has a file path header line (ends with .dart).
      expect(
        out,
        matches(RegExp(r'.+\.dart')),
        reason: 'human output must contain file header lines',
      );
    },
  );

  test(
    'loam scan --format human: plain mode — no ANSI escapes in subprocess output',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'human',
        'scan',
        '--project-root',
        fixturePath,
      ]);
      final out = result.stdout as String;
      // Subprocess is not a TTY → isTty=false → no ANSI escapes.
      expect(out, isNot(contains('\x1B')));
    },
  );

  test(
    'loam scan --format human: output contains summary footer with "finding"',
    () {
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        '--format',
        'human',
        'scan',
        '--project-root',
        fixturePath,
      ]);
      final out = result.stdout as String;
      expect(
        out,
        contains('finding'),
        reason: 'summary footer must mention "finding"',
      );
    },
  );

  // ---------------------------------------------------------------------------
  // AC6: unsupported format → exit 64, clear message to stderr
  // ---------------------------------------------------------------------------

  test('loam scan --format markdown: exit 64 with clear error message', () {
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
      equals(64),
      reason: 'unsupported format should exit 64 (EX_USAGE)',
    );
    final err = result.stderr as String;
    expect(
      err,
      contains('markdown'),
      reason: 'stderr must name the unsupported format',
    );
  });
}

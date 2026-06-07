@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;

/// CLI-level proof for AC3: a malformed/invalid `loam.yaml` run through a
/// command's `run()`/`_loadConfig` dispatch yields a clean error message and a
/// non-zero exit code — and NO raw Dart stacktrace surfaces (stacktrace-free).
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('loam_config_err_cli_');
    // Minimal valid Dart package so the runner can load the project.
    File(p.join(tempDir.path, 'pubspec.yaml')).writeAsStringSync('''
name: broken_config_project
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
    Directory(p.join(tempDir.path, 'lib')).createSync();
    File(
      p.join(tempDir.path, 'lib', 'clean.dart'),
    ).writeAsStringSync('// empty library\n');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  // ---------------------------------------------------------------------------
  // In-process: exit code is non-zero (not a thrown stacktrace) for each command
  // ---------------------------------------------------------------------------

  test('scan with syntax-broken loam.yaml → non-zero exit, no throw', () async {
    File(
      p.join(tempDir.path, 'loam.yaml'),
    ).writeAsStringSync('rules: {broken: yaml: here\n');

    final code = await cli.run(['scan', '--project-root', tempDir.path]);
    expect(code, isNot(0), reason: 'malformed config must fail with non-zero');
  });

  test('gate with syntax-broken loam.yaml → non-zero exit, no throw', () async {
    File(
      p.join(tempDir.path, 'loam.yaml'),
    ).writeAsStringSync('rules: {broken: yaml: here\n');

    final code = await cli.run([
      'gate',
      '--absolute',
      '--project-root',
      tempDir.path,
    ]);
    expect(code, isNot(0), reason: 'malformed config must fail with non-zero');
  });

  test(
    'baseline --write with syntax-broken loam.yaml → non-zero exit, no throw',
    () async {
      File(
        p.join(tempDir.path, 'loam.yaml'),
      ).writeAsStringSync('rules: {broken: yaml: here\n');

      final code = await cli.run([
        'baseline',
        '--write',
        '--project-root',
        tempDir.path,
      ]);
      expect(
        code,
        isNot(0),
        reason: 'malformed config must fail with non-zero',
      );
    },
  );

  test(
    'scan with unknown ruleId in loam.yaml → non-zero exit, no throw',
    () async {
      File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync('''
rules:
  typo-rule-id: false
''');

      final code = await cli.run(['scan', '--project-root', tempDir.path]);
      expect(code, isNot(0), reason: 'unknown ruleId must fail with non-zero');
    },
  );

  // ---------------------------------------------------------------------------
  // Subprocess: stderr carries a clean one-line message and NO raw stacktrace
  // ---------------------------------------------------------------------------

  test(
    'scan with malformed loam.yaml → clean stderr message, no stacktrace',
    () {
      File(
        p.join(tempDir.path, 'loam.yaml'),
      ).writeAsStringSync('rules: {broken: yaml: here\n');

      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'scan',
        '--project-root',
        tempDir.path,
      ]);

      expect(result.exitCode, isNot(0));
      final err = result.stderr as String;
      // Clean, human-readable message present.
      expect(err.trim(), isNotEmpty);
      expect(err, contains('config error'));
      // No raw Dart stacktrace markers.
      expect(
        err,
        isNot(contains('#0 ')),
        reason: 'stderr must not contain a raw stacktrace frame',
      );
      expect(
        err,
        isNot(contains('package:yaml')),
        reason: 'stderr must not leak internal package frames',
      );
      expect(
        err,
        isNot(contains('Unhandled exception')),
        reason: 'exception must be caught, not crash the process',
      );
    },
  );
}

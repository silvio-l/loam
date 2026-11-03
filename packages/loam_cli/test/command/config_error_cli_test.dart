@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;
import '../support/cli_runner.dart';
import '../support/shared_store.dart';

/// CLI-level proof for AC3: a malformed/invalid `loam.yaml` run through a
/// command's `run()`/`_loadConfig` dispatch yields a clean error message and a
/// non-zero exit code — and NO raw Dart stacktrace surfaces (stacktrace-free).
void main() {
  useSharedAnalyzerStore();

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

  test('malformed loam.yaml → stderr message without stacktrace', () async {
    File(
      p.join(tempDir.path, 'loam.yaml'),
    ).writeAsStringSync('rules: {broken: yaml: here\n');

    final r = await runCli(['scan', '--project-root', tempDir.path]);

    expect(r.exitCode, isNot(0));
    expect(r.stderr.trim(), isNotEmpty);
    expect(r.stderr, isNot(contains('#0 ')));
    expect(r.stderr, isNot(contains('package:yaml')));
    expect(r.stderr, isNot(contains('Unhandled exception')));
  });
}

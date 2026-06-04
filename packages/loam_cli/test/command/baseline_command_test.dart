@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/baseline/baseline_engine.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;

/// Creates a minimal Dart package (no public symbols → no findings).
Directory _makeCleanProject() {
  final dir = Directory.systemTemp.createTempSync('loam_baseline_cmd_test_');
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: clean_pkg
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
  Directory(p.join(dir.path, 'lib')).createSync();
  File(p.join(dir.path, 'lib', 'clean.dart')).writeAsStringSync('// empty\n');
  return dir;
}

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = _makeCleanProject();
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  // ---------------------------------------------------------------------------
  // AC5: loam baseline --write creates baseline.json; warns on existing file
  // ---------------------------------------------------------------------------

  group('loam baseline --write', () {
    test('--write creates baseline.json and exits 0', () async {
      final code = await cli.run([
        'baseline',
        '--write',
        '--project-root',
        tempDir.path,
      ]);
      expect(code, equals(0));
      expect(
        File(p.join(tempDir.path, 'baseline.json')).existsSync(),
        isTrue,
        reason: 'baseline.json must be created by --write',
      );
    });

    test(
      '--write baseline.json contains rulesetVersion from AnalysisRunner',
      () async {
        await cli.run(['baseline', '--write', '--project-root', tempDir.path]);

        final engine = BaselineEngine(projectRoot: tempDir.path);
        final baseline = engine.read();
        expect(
          baseline.rulesetVersion,
          equals(AnalysisRunner.rulesetVersion),
          reason: 'rulesetVersion must match AnalysisRunner.rulesetVersion',
        );
      },
    );

    test('--write warns when baseline.json already exists (subprocess)', () {
      // Pre-create a baseline.json
      final engine = BaselineEngine(projectRoot: tempDir.path);
      engine.write([], AnalysisRunner.rulesetVersion);

      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'baseline',
        '--write',
        '--project-root',
        tempDir.path,
      ]);
      // Should still succeed (exit 0) but print a warning
      expect(result.exitCode, equals(0));
      final combined = '${result.stdout}${result.stderr}';
      expect(
        combined.toLowerCase(),
        anyOf(
          contains('warn'),
          contains('already exists'),
          contains('--update'),
        ),
        reason: 'must warn that baseline.json exists and hint at --update',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC6: loam baseline --update writes into existing; warns if none exists
  // ---------------------------------------------------------------------------

  group('loam baseline --update', () {
    test('--update writes into existing baseline.json and exits 0', () async {
      // Create a baseline first
      await cli.run(['baseline', '--write', '--project-root', tempDir.path]);

      final code = await cli.run([
        'baseline',
        '--update',
        '--project-root',
        tempDir.path,
      ]);
      expect(code, equals(0));
      expect(File(p.join(tempDir.path, 'baseline.json')).existsSync(), isTrue);
    });

    test('--update warns when baseline.json does NOT exist (subprocess)', () {
      // No baseline.json exists yet
      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'baseline',
        '--update',
        '--project-root',
        tempDir.path,
      ]);
      // Should still succeed (exit 0) but print a warning
      expect(result.exitCode, equals(0));
      final combined = '${result.stdout}${result.stderr}';
      expect(
        combined.toLowerCase(),
        anyOf(contains('warn'), contains('no baseline'), contains('--write')),
        reason: 'must warn that no baseline.json exists and hint at --write',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC4: loam baseline (no flag) shows current baseline count + context
  // ---------------------------------------------------------------------------

  group('loam baseline (no flag)', () {
    test('with existing baseline.json: exits 0 and shows count', () async {
      // Write a baseline first
      final engine = BaselineEngine(projectRoot: tempDir.path);
      engine.write([], AnalysisRunner.rulesetVersion);

      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'baseline',
        '--project-root',
        tempDir.path,
      ]);
      expect(result.exitCode, equals(0));
      final out = result.stdout as String;
      // Should mention finding count
      expect(
        out,
        anyOf(contains('0 finding'), contains('finding')),
        reason: 'output must mention finding count',
      );
    });

    test('with no baseline.json: exits non-zero or shows clear error message', () {
      // No baseline.json exists
      final entrypoint = '${Directory.current.path}/bin/loam.dart';
      final result = Process.runSync(Platform.executable, [
        'run',
        entrypoint,
        'baseline',
        '--project-root',
        tempDir.path,
      ]);
      final combined = '${result.stdout}${result.stderr}';
      // Should either exit non-zero or show a helpful message about missing baseline
      final hasHelpfulOutput =
          combined.toLowerCase().contains('missing') ||
          combined.toLowerCase().contains('no baseline') ||
          combined.toLowerCase().contains('--write') ||
          result.exitCode != 0;
      expect(
        hasHelpfulOutput,
        isTrue,
        reason:
            'must show helpful message or non-zero exit when no baseline.json',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC7: rulesetVersion is derived from AnalysisRunner.rulesetVersion
  // ---------------------------------------------------------------------------

  test(
    'rulesetVersion in baseline.json matches AnalysisRunner.rulesetVersion',
    () async {
      await cli.run(['baseline', '--write', '--project-root', tempDir.path]);
      final engine = BaselineEngine(projectRoot: tempDir.path);
      final baseline = engine.read();
      expect(baseline.rulesetVersion, equals(AnalysisRunner.rulesetVersion));
      // Not a raw hardcoded string:
      expect(baseline.rulesetVersion, startsWith('ruleset@'));
      expect(baseline.rulesetVersion.length, greaterThan('ruleset@'.length));
    },
  );
}

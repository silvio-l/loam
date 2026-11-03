@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:loam/src/baseline/baseline_engine.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/cli_runner.dart';

/// Gate / baseline behaviour, driven through the real entry point in-process.
///
/// One journey covers the ratchet lifecycle (scan → baseline → gate → regression
/// → fix); the remaining tests pin exit codes of the edge cases and the
/// machine-readable SARIF output that gate and baseline embed. Message wording
/// is deliberately not asserted.

/// Creates a fresh temp project per test and deletes it when that test ends, so
/// an overrunning test can never remove the directory of the next one.
Directory _makeProject({bool withFinding = false}) {
  final dir = Directory.systemTemp.createTempSync('loam_gate_flow_');
  addTearDown(() => dir.deleteSync(recursive: true));
  File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: gate_flow_pkg
publish_to: none
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
  Directory(p.join(dir.path, 'lib')).createSync();
  File(p.join(dir.path, 'lib', 'lib.dart')).writeAsStringSync('// empty\n');
  if (withFinding) _addUnusedExport(dir, 'frozen_unused');
  return dir;
}

/// Adds an unused public class so that `unused-public-exports` fires.
void _addUnusedExport(Directory dir, String name) {
  File(
    p.join(dir.path, 'lib', '$name.dart'),
  ).writeAsStringSync('class ${name.replaceAll('_', '')} {}\n');
}

/// The whole stdout must be one JSON document: summary lines and hints belong
/// on stderr, otherwise `loam ... --format json | jq` breaks.
Object? _stdoutJson(String out) => jsonDecode(out);

void main() {
  late JsonSchema sarifSchema;

  setUpAll(() {
    sarifSchema = JsonSchema.create(
      jsonDecode(
            File(
              p.join('test', 'fixtures', 'sarif', 'sarif-schema-2.1.0.json'),
            ).readAsStringSync(),
          )
          as Map<String, dynamic>,
    );
  });

  test('ratchet journey: scan → baseline → gate green → regression red → '
      'fixed green', () async {
    final dir = _makeProject(withFinding: true);
    final root = ['--project-root', dir.path];

    expect((await runCli(['scan', ...root])).exitCode, 1);
    expect((await runCli(['baseline', '--write', ...root])).exitCode, 0);
    expect(File(p.join(dir.path, 'baseline.json')).existsSync(), isTrue);
    expect(
      (await runCli(['gate', ...root])).exitCode,
      0,
      reason: 'the existing finding is frozen in the baseline',
    );

    _addUnusedExport(dir, 'new_unused');
    expect((await runCli(['gate', ...root])).exitCode, 1);

    File(p.join(dir.path, 'lib', 'new_unused.dart')).deleteSync();
    expect((await runCli(['gate', ...root])).exitCode, 0);
  });

  group('gate --absolute needs no baseline', () {
    test('findings → exit 1', () async {
      final dir = _makeProject(withFinding: true);
      final r = await runCli([
        'gate',
        '--absolute',
        '--project-root',
        dir.path,
      ]);
      expect(r.exitCode, 1);
    });

    test('clean project → exit 0', () async {
      final dir = _makeProject();
      final r = await runCli([
        'gate',
        '--absolute',
        '--project-root',
        dir.path,
      ]);
      expect(r.exitCode, 0);
    });

    test('unused and expired loam-ignore only warn, exit stays 0', () async {
      final dir = _makeProject();
      File(p.join(dir.path, 'lib', 'stale.dart')).writeAsStringSync(
        '// loam-ignore: unused-public-exports – nothing here to suppress\n'
        '// loam-ignore: unused-public-exports until=2000-01-01 – long expired\n'
        'int _answer() => 42;\n',
      );
      final r = await runCli([
        'gate',
        '--absolute',
        '--project-root',
        dir.path,
      ]);
      expect(r.exitCode, 0, reason: r.stderr);
      expect(r.stderr, contains('unused'));
      expect(r.stderr, contains('expired'));
    });
  });

  group('baseline handling', () {
    test('gate without baseline.json → exit 66, error on stderr', () async {
      final dir = _makeProject();
      final r = await runCli(['gate', '--project-root', dir.path]);
      expect(r.exitCode, 66);
      expect(r.stderr.trim(), isNotEmpty);
      expect(r.stderr, isNot(contains('Unhandled exception')));
    });

    test('baseline.json carries the current rulesetVersion', () async {
      final dir = _makeProject();
      await runCli(['baseline', '--write', '--project-root', dir.path]);
      final baseline = BaselineEngine(projectRoot: dir.path).read();
      expect(baseline.rulesetVersion, AnalysisRunner.rulesetVersion);
    });

    test('--write over an existing baseline → exit 0 with a warning', () async {
      final dir = _makeProject();
      BaselineEngine(
        projectRoot: dir.path,
      ).write([], AnalysisRunner.rulesetVersion);
      final r = await runCli([
        'baseline',
        '--write',
        '--project-root',
        dir.path,
      ]);
      expect(r.exitCode, 0);
      expect('${r.stdout}${r.stderr}', isNotEmpty);
    });

    test('--update without a baseline → exit 0 with a warning', () async {
      final dir = _makeProject();
      final r = await runCli([
        'baseline',
        '--update',
        '--project-root',
        dir.path,
      ]);
      expect(r.exitCode, 0);
      expect('${r.stdout}${r.stderr}', isNotEmpty);
    });

    test('--update with an existing baseline → exit 0', () async {
      final dir = _makeProject();
      await runCli(['baseline', '--write', '--project-root', dir.path]);
      final r = await runCli([
        'baseline',
        '--update',
        '--project-root',
        dir.path,
      ]);
      expect(r.exitCode, 0);
    });

    test('stale rulesetVersion → warning on stderr, gate still runs', () async {
      final dir = _makeProject();
      await runCli(['baseline', '--write', '--project-root', dir.path]);
      final file = File(p.join(dir.path, 'baseline.json'));
      file.writeAsStringSync(
        file.readAsStringSync().replaceFirst(
          RegExp(r'"rulesetVersion":\s*"[^"]*"'),
          '"rulesetVersion": "ruleset@stale000"',
        ),
      );
      final r = await runCli(['gate', '--project-root', dir.path]);
      expect(r.exitCode, 0);
      expect(r.stderr.trim(), isNotEmpty);
    });
  });

  group('SARIF embedded by gate and baseline is schema-valid', () {
    test('gate --format sarif with a new finding', () async {
      final dir = _makeProject();
      await runCli(['baseline', '--write', '--project-root', dir.path]);
      _addUnusedExport(dir, 'new_unused');
      final r = await runCli([
        '--format',
        'sarif',
        'gate',
        '--project-root',
        dir.path,
      ]);
      expect(r.exitCode, 1);
      final result = sarifSchema.validate(_stdoutJson(r.stdout));
      expect(result.isValid, isTrue, reason: '${result.errors}');
    });

    test('baseline --format sarif shows the frozen findings', () async {
      final dir = _makeProject(withFinding: true);
      await runCli(['baseline', '--write', '--project-root', dir.path]);
      final r = await runCli([
        '--format',
        'sarif',
        'baseline',
        '--project-root',
        dir.path,
      ]);
      expect(r.exitCode, 0);
      final result = sarifSchema.validate(_stdoutJson(r.stdout));
      expect(result.isValid, isTrue, reason: '${result.errors}');
    });

    test('machine-readable formats keep stdout a pure document, also when the '
        'gate is green', () async {
      final dir = _makeProject();
      await runCli(['baseline', '--write', '--project-root', dir.path]);
      for (final mode in [
        <String>[],
        ['--absolute'],
      ]) {
        for (final format in ['json', 'sarif']) {
          final r = await runCli([
            '--format',
            format,
            'gate',
            ...mode,
            '--project-root',
            dir.path,
          ]);
          expect(r.exitCode, 0, reason: '$format $mode');
          expect(_stdoutJson(r.stdout), isA<Map<String, dynamic>>());
          expect(r.stderr, isNotEmpty, reason: 'summary moved to stderr');
        }
      }
    });

    test('gate --format json --absolute carries a parseable report', () async {
      final dir = _makeProject(withFinding: true);
      final r = await runCli([
        '--format',
        'json',
        'gate',
        '--absolute',
        '--project-root',
        dir.path,
      ]);
      expect(r.exitCode, 1);
      expect(_stdoutJson(r.stdout), isA<Map<String, dynamic>>());
    });
  });

  group('stale baseline entries', () {
    List<String> baselineFingerprints(Directory dir) => BaselineEngine(
      projectRoot: dir.path,
    ).read().findings.map((f) => f.fingerprint).toList();

    test('reported by default, red with --strict-baseline or strict_baseline, '
        'gone after --prune', () async {
      final dir = _makeProject(withFinding: true);
      final root = ['--project-root', dir.path];
      await runCli(['baseline', '--write', ...root]);
      final frozen = baselineFingerprints(dir);
      expect(frozen, hasLength(1));

      // Fix the finding: its baseline entry is now stale.
      File(p.join(dir.path, 'lib', 'frozen_unused.dart')).deleteSync();

      final report = await runCli(['gate', ...root]);
      expect(report.exitCode, 0, reason: 'default: only report');
      expect(report.stderr, contains('unused-public-exports: 1'));

      expect(
        (await runCli(['gate', '--strict-baseline', ...root])).exitCode,
        1,
      );

      File(
        p.join(dir.path, 'loam.yaml'),
      ).writeAsStringSync('strict_baseline: true\n');
      expect((await runCli(['gate', ...root])).exitCode, 1);
      expect(
        (await runCli(['gate', '--no-strict-baseline', ...root])).exitCode,
        0,
        reason: 'the flag overrides loam.yaml',
      );

      final pruned = await runCli(['baseline', '--prune', ...root]);
      expect(pruned.exitCode, 0, reason: pruned.stderr);
      expect(baselineFingerprints(dir), isEmpty);
      expect((await runCli(['gate', ...root])).exitCode, 0);
    });

    test(
      'prune takes in nothing new and keeps still-occurring entries',
      () async {
        final dir = _makeProject(withFinding: true);
        final root = ['--project-root', dir.path];
        await runCli(['baseline', '--write', ...root]);
        final frozen = baselineFingerprints(dir);
        _addUnusedExport(dir, 'brand_new');

        expect((await runCli(['baseline', '--prune', ...root])).exitCode, 0);
        expect(baselineFingerprints(dir), frozen);
      },
    );

    test('usage errors: --prune with --write, --strict-baseline with '
        '--absolute, --prune without a baseline', () async {
      final dir = _makeProject();
      final root = ['--project-root', dir.path];
      expect(
        (await runCli(['baseline', '--prune', '--write', ...root])).exitCode,
        64,
      );
      expect(
        (await runCli([
          'gate',
          '--absolute',
          '--strict-baseline',
          ...root,
        ])).exitCode,
        64,
      );
      expect((await runCli(['baseline', '--prune', ...root])).exitCode, 66);
    });
  });
}

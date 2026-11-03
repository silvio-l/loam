@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;
import '../support/shared_store.dart';

/// Wiring of `--staged` / `--since` / `--changed` against a real git repo:
/// the analysis stays project-wide, only report and gate are narrowed.
void main() {
  useSharedAnalyzerStore();

  late Directory project;

  ProcessResult git(List<String> args) => Process.runSync('git', [
    '-c',
    'user.name=t',
    '-c',
    'user.email=t@t',
    // Independent of the machine's git setup (signing, global hooks).
    '-c',
    'commit.gpgsign=false',
    '-c',
    'core.hooksPath=/dev/null',
    ...args,
  ], workingDirectory: project.path);

  void write(String name) => File(
    p.join(project.path, 'lib', name),
  ).writeAsStringSync('class ${name.split('.').first.toUpperCase()} {}\n');

  setUp(() {
    project = Directory.systemTemp.createTempSync('loam_changed_');
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: changed_project
publish_to: none
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
    Directory(p.join(project.path, 'lib')).createSync();
    write('old.dart'); // unused public export, committed => not "changed"
  });

  tearDown(() => project.deleteSync(recursive: true));

  Future<int> run(List<String> args) => cli.run([
    '--no-update-check',
    '--no-progress',
    ...args,
    '--project-root',
    project.path,
  ]);

  test('outside a git repository exits 64', () async {
    expect(await run(['scan', '--staged']), 64);
  });

  test('unknown --since ref exits 64', () async {
    git(['init', '-q']);
    git(['add', 'pubspec.yaml', 'lib/old.dart']);
    git(['commit', '-q', '-m', 'init']);
    expect(await run(['scan', '--since', 'no-such-ref']), 64);
  });

  test('scan --changed reports only changed files; gate follows', () async {
    git(['init', '-q']);
    git(['add', 'pubspec.yaml', 'lib/old.dart']);
    git(['commit', '-q', '-m', 'init']);

    // Whole project: the committed unused export is a finding.
    expect(await run(['scan']), 1);
    // Nothing changed: its finding is out of scope.
    expect(await run(['scan', '--changed']), 0);
    expect(await run(['gate', '--absolute', '--changed']), 0);

    // A new untracked file with its own finding is in scope.
    write('fresh.dart');
    expect(await run(['scan', '--changed']), 1);
    expect(await run(['gate', '--absolute', '--changed']), 1);
    // ...but not once only a different file is staged.
    git(['add', 'pubspec.yaml']);
    expect(await run(['scan', '--staged']), 0);
    git(['add', 'lib/fresh.dart']);
    expect(await run(['scan', '--staged']), 1);
  });

  test('scan --changed keeps the suppression audit', () async {
    git(['init', '-q']);
    git(['add', 'pubspec.yaml', 'lib/old.dart']);
    git(['commit', '-q', '-m', 'init']);
    File(p.join(project.path, 'lib', 'fresh.dart')).writeAsStringSync(
      '// loam-ignore: code-duplicates – nothing here to suppress\n'
      'class Fresh {}\n',
    );
    final out = p.join(project.path, 'report.json');
    await run(['scan', '--changed', '--format', 'json', '--output', out]);
    final report = jsonDecode(File(out).readAsStringSync()) as Map;
    expect(report['suppression'], isNotNull);
  });

  test('ratchet gate: the baseline diff is narrowed, not recomputed', () async {
    git(['init', '-q']);
    git(['add', 'pubspec.yaml', 'lib/old.dart']);
    git(['commit', '-q', '-m', 'init']);
    expect(await run(['baseline', '--write']), 0);

    // Frozen finding in an unchanged file: neither new nor in scope.
    expect(await run(['gate', '--changed']), 0);
    // A new finding in a changed file fails the narrowed ratchet.
    write('fresh.dart');
    expect(await run(['gate', '--changed']), 1);
  });
}

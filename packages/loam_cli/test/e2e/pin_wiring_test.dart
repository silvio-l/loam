@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;
import '../support/shared_store.dart';

/// Wiring of `required_version`: a violated pin stops `loam gate` with 78,
/// other commands only warn. `--no-update-check` keeps the run offline and
/// free of background workers.
void main() {
  useSharedAnalyzerStore();

  late Directory project;

  setUp(() {
    project = Directory.systemTemp.createTempSync('loam_pin_');
    File(p.join(project.path, 'pubspec.yaml')).writeAsStringSync('''
name: pinned_project
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
    Directory(p.join(project.path, 'lib')).createSync();
    File(p.join(project.path, 'lib', 'a.dart')).writeAsStringSync('// empty\n');
    File(
      p.join(project.path, 'loam.yaml'),
    ).writeAsStringSync('required_version: "99.0.0"\n');
  });

  tearDown(() => project.deleteSync(recursive: true));

  test('violated pin: loam gate exits 78', () async {
    final code = await cli.run([
      '--no-update-check',
      'gate',
      '--project-root',
      project.path,
    ]);
    expect(code, 78);
  });

  test('violated pin: scan only warns, exit is not 78', () async {
    final code = await cli.run([
      '--no-update-check',
      'scan',
      '--project-root',
      project.path,
    ]);
    expect(code, isNot(78));
  });
}

@TestOn('vm')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;
import '../support/shared_store.dart';

/// CLI proof: the profile decides what blocks, never what is in the baseline.
void main() {
  useSharedAnalyzerStore();

  late Directory dir;

  Future<int> gate(List<String> extra) =>
      cli.run(['gate', '--project-root', dir.path, ...extra]);

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('loam_gate_profile_');
    File(p.join(dir.path, 'pubspec.yaml')).writeAsStringSync('''
name: gate_profile_pkg
publish_to: none
environment:
  sdk: ">=3.0.0 <4.0.0"
''');
    Directory(p.join(dir.path, 'lib')).createSync();
    File(p.join(dir.path, 'lib', 'lib.dart')).writeAsStringSync('// empty\n');
    expect(
      await cli.run(['baseline', '--write', '--project-root', dir.path]),
      0,
    );
    // A new finding of a strict-profile rule (slop-narrative-comment: the
    // comment only repeats the name). The core rule on the unused function is
    // switched off so only the strict rule is in play.
    File(p.join(dir.path, 'lib', 'a.dart')).writeAsStringSync('''
// helper
void helper() {}
''');
  });

  tearDownAll(() => dir.deleteSync(recursive: true));

  void setProfile(String? profile) =>
      File(p.join(dir.path, 'loam.yaml')).writeAsStringSync(
        'rules:\n  unused-public-exports: false\n'
        '${profile == null ? '' : 'profile: $profile\n'}',
      );

  // The project is built once; every test starts from the same loam.yaml.
  setUp(() => setProfile(null));

  test(
    'default (core): green, the strict-rule finding is only a hint',
    () async {
      expect(await gate([]), 0);
    },
  );

  test('--profile strict blocks the same finding', () async {
    expect(await gate(['--profile', 'strict']), 1);
  });

  test('profile: strict in loam.yaml blocks', () async {
    setProfile('strict');
    expect(await gate([]), 1);
  });

  test(
    'CLI beats loam.yaml: --profile core overrides profile: strict',
    () async {
      setProfile('strict');
      expect(await gate(['--profile', 'core']), 0);
    },
  );

  test('absolute mode honours the profile as well', () async {
    expect(await gate(['--absolute']), 0);
    expect(await gate(['--absolute', '--profile', 'strict']), 1);
  });

  test('unknown --profile → exit 64', () async {
    expect(await gate(['--profile', 'standard']), 64);
  });

  test('unknown profile in loam.yaml → exit 78', () async {
    setProfile('standard');
    expect(await gate([]), 78);
  });
}

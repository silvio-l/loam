@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/config_loader.dart';
import 'package:loam/src/rules/rule_profile.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../support/shared_store.dart';

void main() {
  useSharedAnalyzerStore();

  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('loam_profile_cfg_'));
  tearDown(() => dir.deleteSync(recursive: true));

  void writeYaml(String content, [String sub = '']) {
    final d = Directory(p.join(dir.path, sub))..createSync(recursive: true);
    File(p.join(d.path, 'loam.yaml')).writeAsStringSync(content);
  }

  test('no loam.yaml → profile unset', () async {
    expect((await ConfigLoader.load(dir.path)).profile, isNull);
  });

  test('profile: strict is parsed', () async {
    writeYaml('profile: strict\n');
    expect((await ConfigLoader.load(dir.path)).profile, RuleProfile.strict);
  });

  test('unknown profile name → ConfigLoadException naming the choices', () {
    writeYaml('profile: standard\n');
    expect(
      ConfigLoader.load(dir.path),
      throwsA(
        isA<ConfigLoadException>().having(
          (e) => e.message,
          'message',
          allOf(contains('core'), contains('strict'), contains('standard')),
        ),
      ),
    );
  });

  test('non-string profile → ConfigLoadException', () {
    writeYaml('profile: true\n');
    expect(ConfigLoader.load(dir.path), throwsA(isA<ConfigLoadException>()));
  });

  test('nearer layer wins, an omitting layer inherits', () async {
    Directory(p.join(dir.path, '.git')).createSync();
    writeYaml('profile: strict\n');
    writeYaml('rules: {}\n', 'pkg');
    expect(
      (await ConfigLoader.load(p.join(dir.path, 'pkg'))).profile,
      RuleProfile.strict,
    );
    writeYaml('profile: core\n', 'pkg');
    expect(
      (await ConfigLoader.load(p.join(dir.path, 'pkg'))).profile,
      RuleProfile.core,
    );
  });
}

@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/config_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('loam_config_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  // ---------------------------------------------------------------------------
  // AC1: Missing file → LoamConfig.defaults()
  // ---------------------------------------------------------------------------

  test('missing loam.yaml returns LoamConfig.defaults()', () async {
    final config = await ConfigLoader.load(tempDir.path);
    expect(config.ruleToggles, isEmpty);
    expect(config.ignoreGlobs, isEmpty);
  });

  // ---------------------------------------------------------------------------
  // AC2: Valid loam.yaml with rule-toggle is parsed correctly
  // ---------------------------------------------------------------------------

  test('valid loam.yaml with rule-toggle parses correctly', () async {
    final yaml = '''
rules:
  unused-public-exports: false
''';
    File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync(yaml);

    final config = await ConfigLoader.load(tempDir.path);
    expect(config.ruleToggles, equals({'unused-public-exports': false}));
  });

  test('valid loam.yaml with rule enabled (true) parses correctly', () async {
    final yaml = '''
rules:
  unused-public-exports: true
''';
    File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync(yaml);

    final config = await ConfigLoader.load(tempDir.path);
    expect(config.ruleToggles, equals({'unused-public-exports': true}));
  });

  // ---------------------------------------------------------------------------
  // AC3: Syntax error → ConfigLoadException (no raw stacktrace to surface)
  // ---------------------------------------------------------------------------

  test('syntax-broken loam.yaml throws ConfigLoadException', () async {
    // Invalid YAML: unbalanced braces
    File(
      p.join(tempDir.path, 'loam.yaml'),
    ).writeAsStringSync('rules: {broken: yaml: here\n');

    await expectLater(
      ConfigLoader.load(tempDir.path),
      throwsA(isA<ConfigLoadException>()),
    );
  });

  test('ConfigLoadException carries a human-readable message', () async {
    File(
      p.join(tempDir.path, 'loam.yaml'),
    ).writeAsStringSync('rules: {broken: yaml: here\n');

    try {
      await ConfigLoader.load(tempDir.path);
      fail('Expected ConfigLoadException');
    } on ConfigLoadException catch (e) {
      expect(e.message, isNotEmpty);
      // No raw Dart stacktrace in the message
      expect(e.message, isNot(contains('package:yaml')));
    }
  });

  // ---------------------------------------------------------------------------
  // AC4: Unknown ruleId in toggle → ConfigLoadException (reported, not silent)
  // ---------------------------------------------------------------------------

  test('unknown ruleId in toggle throws ConfigLoadException', () async {
    final yaml = '''
rules:
  not-a-real-rule: false
''';
    File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync(yaml);

    // Must supply known rule IDs so the loader can validate
    await expectLater(
      ConfigLoader.load(tempDir.path, knownRuleIds: {'unused-public-exports'}),
      throwsA(isA<ConfigLoadException>()),
    );
  });

  test('unknown ruleId error message mentions the unknown id', () async {
    final yaml = '''
rules:
  typo-rule-id: false
''';
    File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync(yaml);

    try {
      await ConfigLoader.load(
        tempDir.path,
        knownRuleIds: {'unused-public-exports'},
      );
      fail('Expected ConfigLoadException');
    } on ConfigLoadException catch (e) {
      expect(e.message, contains('typo-rule-id'));
    }
  });

  test('load without knownRuleIds skips unknown-ruleId validation', () async {
    // When no knownRuleIds are supplied (e.g. called without the registry),
    // unknown IDs should NOT throw — validation is opt-in.
    final yaml = '''
rules:
  some-future-rule: false
''';
    File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync(yaml);

    final config = await ConfigLoader.load(tempDir.path);
    expect(config.ruleToggles, equals({'some-future-rule': false}));
  });

  // ---------------------------------------------------------------------------
  // ignore globs placeholder: present on model, empty by default
  // ---------------------------------------------------------------------------

  test('loam.yaml with ignore globs parses ignore list', () async {
    final yaml = '''
ignore:
  - "test/fixtures/**"
  - "lib/generated/**"
''';
    File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync(yaml);

    final config = await ConfigLoader.load(tempDir.path);
    expect(
      config.ignoreGlobs,
      containsAll(['test/fixtures/**', 'lib/generated/**']),
    );
  });
}

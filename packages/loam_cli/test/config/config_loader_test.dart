@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/config_loader.dart';
import 'package:loam/src/config/loam_config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../support/shared_store.dart';

void main() {
  useSharedAnalyzerStore();

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

  // ---------------------------------------------------------------------------
  // auto_update / required_version (auto-update pin, #9)
  // ---------------------------------------------------------------------------

  test('no config → auto_update on, no version pin', () async {
    final config = await ConfigLoader.load(tempDir.path);
    expect(config.autoUpdate, isTrue);
    expect(config.requiredVersion, isNull);
  });

  test('auto_update: false and a required_version range parse', () async {
    File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync(
      'auto_update: false\nrequired_version: ">=0.1.15 <0.2.0"\n',
    );
    final config = await ConfigLoader.load(tempDir.path);
    expect(config.autoUpdate, isFalse);
    expect(config.requiredVersion.toString(), '>=0.1.15 <0.2.0');
  });

  test('invalid required_version or non-bool auto_update → '
      'ConfigLoadException', () async {
    final file = File(p.join(tempDir.path, 'loam.yaml'));
    file.writeAsStringSync('required_version: "latest please"\n');
    await expectLater(
      ConfigLoader.load(tempDir.path),
      throwsA(isA<ConfigLoadException>()),
    );
    file.writeAsStringSync('auto_update: "no"\n');
    await expectLater(
      ConfigLoader.load(tempDir.path),
      throwsA(isA<ConfigLoadException>()),
    );
  });

  // ---------------------------------------------------------------------------
  // update_check field
  // ---------------------------------------------------------------------------

  test('missing update_check field defaults to true (Zero-Config)', () async {
    // No loam.yaml at all → defaults.
    final config = await ConfigLoader.load(tempDir.path);
    expect(config.updateCheck, isTrue);
  });

  test('update_check: true parses correctly', () async {
    File(
      p.join(tempDir.path, 'loam.yaml'),
    ).writeAsStringSync('update_check: true\n');
    final config = await ConfigLoader.load(tempDir.path);
    expect(config.updateCheck, isTrue);
  });

  test('update_check: false parses correctly', () async {
    File(
      p.join(tempDir.path, 'loam.yaml'),
    ).writeAsStringSync('update_check: false\n');
    final config = await ConfigLoader.load(tempDir.path);
    expect(config.updateCheck, isFalse);
  });

  test('update_check with non-bool value throws ConfigLoadException', () async {
    File(
      p.join(tempDir.path, 'loam.yaml'),
    ).writeAsStringSync('update_check: "yes"\n');

    await expectLater(
      ConfigLoader.load(tempDir.path),
      throwsA(isA<ConfigLoadException>()),
    );
  });

  test('update_check non-bool error message mentions the field', () async {
    File(
      p.join(tempDir.path, 'loam.yaml'),
    ).writeAsStringSync('update_check: 1\n');

    try {
      await ConfigLoader.load(tempDir.path);
      fail('Expected ConfigLoadException');
    } on ConfigLoadException catch (e) {
      expect(e.message, contains('update_check'));
    }
  });

  test('update_check: false coexists with rule-toggles', () async {
    final yaml = '''
update_check: false
rules:
  unused-public-exports: false
''';
    File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync(yaml);
    final config = await ConfigLoader.load(tempDir.path);
    expect(config.updateCheck, isFalse);
    expect(config.ruleToggles, equals({'unused-public-exports': false}));
  });

  // ---------------------------------------------------------------------------
  // LoamConfig equality and hashCode — updateCheck field participates
  // ---------------------------------------------------------------------------

  group('LoamConfig == and hashCode with updateCheck', () {
    test('two defaults() are equal', () {
      expect(const LoamConfig.defaults(), equals(const LoamConfig.defaults()));
    });

    test('updateCheck=true vs updateCheck=false are not equal', () {
      const a = LoamConfig(ruleToggles: {}, ignoreGlobs: [], updateCheck: true);
      const b = LoamConfig(
        ruleToggles: {},
        ignoreGlobs: [],
        updateCheck: false,
      );
      expect(a, isNot(equals(b)));
    });

    test('same updateCheck values produce equal configs', () {
      const a = LoamConfig(
        ruleToggles: {},
        ignoreGlobs: [],
        updateCheck: false,
      );
      const b = LoamConfig(
        ruleToggles: {},
        ignoreGlobs: [],
        updateCheck: false,
      );
      expect(a, equals(b));
    });

    test('hashCode differs when updateCheck differs', () {
      const a = LoamConfig(ruleToggles: {}, ignoreGlobs: [], updateCheck: true);
      const b = LoamConfig(
        ruleToggles: {},
        ignoreGlobs: [],
        updateCheck: false,
      );
      // hashCode collision is theoretically possible but unlikely for booleans.
      expect(a.hashCode, isNot(equals(b.hashCode)));
    });

    test('defaults() updateCheck is true', () {
      expect(const LoamConfig.defaults().updateCheck, isTrue);
    });
  });

  // -------------------------------------------------------------------------
  // source_dirs — configurable production-source scope
  // -------------------------------------------------------------------------
  group('source_dirs', () {
    test('absent → default lib + bin', () async {
      File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync('rules:\n');
      final config = await ConfigLoader.load(tempDir.path);
      expect(config.sourceDirs, ['lib', 'bin']);
    });

    test('explicit list overrides the default', () async {
      File(
        p.join(tempDir.path, 'loam.yaml'),
      ).writeAsStringSync('source_dirs:\n  - lib\n  - bin\n  - tool\n');
      final config = await ConfigLoader.load(tempDir.path);
      expect(config.sourceDirs, ['lib', 'bin', 'tool']);
    });

    test(
      'entries are normalised to the top-level segment and deduped',
      () async {
        File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync(
          'source_dirs:\n  - "lib/"\n  - "lib/src"\n  - bin\n',
        );
        final config = await ConfigLoader.load(tempDir.path);
        expect(config.sourceDirs, ['lib', 'bin']);
      },
    );

    test('non-list source_dirs throws ConfigLoadException', () async {
      File(
        p.join(tempDir.path, 'loam.yaml'),
      ).writeAsStringSync('source_dirs: lib\n');
      expect(
        ConfigLoader.load(tempDir.path),
        throwsA(isA<ConfigLoadException>()),
      );
    });

    test('empty entry throws ConfigLoadException', () async {
      File(
        p.join(tempDir.path, 'loam.yaml'),
      ).writeAsStringSync('source_dirs:\n  - ""\n');
      expect(
        ConfigLoader.load(tempDir.path),
        throwsA(isA<ConfigLoadException>()),
      );
    });

    test('defaults() sourceDirs is lib + bin', () {
      expect(const LoamConfig.defaults().sourceDirs, ['lib', 'bin']);
    });
  });

  test(
    'strict_baseline defaults to false, parses true, rejects non-bool',
    () async {
      expect((await ConfigLoader.load(tempDir.path)).strictBaseline, isFalse);
      final file = File(p.join(tempDir.path, 'loam.yaml'));
      file.writeAsStringSync('strict_baseline: true\n');
      expect((await ConfigLoader.load(tempDir.path)).strictBaseline, isTrue);
      file.writeAsStringSync('strict_baseline: "yes"\n');
      await expectLater(
        ConfigLoader.load(tempDir.path),
        throwsA(isA<ConfigLoadException>()),
      );
    },
  );

  group('intended-pattern settings', () {
    test('defaults: boilerplate skipped, no extras', () async {
      final config = await ConfigLoader.load(tempDir.path);
      expect(config.skipBoilerplate, isTrue);
      expect(config.boilerplateMethods, isEmpty);
      expect(config.reservedAnnotations, isEmpty);
      expect(config.assertionFunctions, isEmpty);
    });

    test('slop_assertion_free_test.assertion_functions is parsed', () async {
      File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync('''
slop_assertion_free_test:
  assertion_functions: [expectGolden, checkAll]
''');
      final config = await ConfigLoader.load(tempDir.path);
      expect(config.assertionFunctions, ['expectGolden', 'checkAll']);
    });

    test('parses sections', () async {
      File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync('''
code_duplicates:
  boilerplate: false
  boilerplate_methods: [build, toXml]
unused_public_exports:
  annotations: ["@Keep", Api]
''');
      final config = await ConfigLoader.load(tempDir.path);
      expect(config.skipBoilerplate, isFalse);
      expect(config.boilerplateMethods, ['build', 'toXml']);
      expect(config.reservedAnnotations, ['Keep', 'Api']);
    });

    test('unknown key in a section is rejected', () async {
      File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync('''
code_duplicates:
  boilerplat: false
''');
      await expectLater(
        ConfigLoader.load(tempDir.path),
        throwsA(isA<ConfigLoadException>()),
      );
    });
  });

  group('layer directories', () {
    test('are normalized to project-relative POSIX prefixes', () {
      for (final dir in [
        'lib/core',
        './lib/core',
        'lib/core/',
        r'lib\core',
        r'.\lib\core\',
        ' lib//core ',
        'lib/x/../core',
      ]) {
        expect(ConfigLoader.normalizeLayerDir('core', dir), 'lib/core');
      }
    });

    test('loading applies the normalization', () async {
      File(p.join(tempDir.path, 'loam.yaml')).writeAsStringSync('''
layers:
  core: ./lib/core/
  features: 'lib\\features'
''');
      final config = await ConfigLoader.load(tempDir.path);
      expect(config.layers, {'core': 'lib/core', 'features': 'lib/features'});
    });

    test('absolute, outside or root paths are a config error', () {
      for (final dir in [
        '/lib/core',
        r'C:\project\lib\core',
        'c:/lib',
        '../shared/lib',
        'lib/../../x',
        '.',
        './',
      ]) {
        expect(
          () => ConfigLoader.normalizeLayerDir('core', dir),
          throwsA(
            isA<ConfigLoadException>().having(
              (e) => e.message,
              'message',
              allOf(contains('"core"'), contains('lib/core')),
            ),
          ),
          reason: dir,
        );
      }
    });
  });
}

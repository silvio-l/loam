@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/architecture/layer_detector.dart';
import 'package:loam/src/config/config_loader.dart';
import 'package:loam/src/config/config_scaffold.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../bin/loam.dart' as cli;

void _dart(Directory root, String dir) {
  final d = Directory(p.join(root.path, 'lib', dir))
    ..createSync(recursive: true);
  File(p.join(d.path, 'a.dart')).writeAsStringSync('// x\n');
}

void main() {
  late Directory root;
  setUp(() => root = Directory.systemTemp.createTempSync('loam_layers_'));
  tearDown(() => root.deleteSync(recursive: true));

  group('LayerDetector', () {
    test('detects known layers and only downward-dependency boundaries', () {
      for (final d in ['core', 'data', 'domain', 'presentation', 'l10n']) {
        _dart(root, d);
      }
      final a = LayerDetector.detect(root.path);

      expect(a.layers, {
        'core': 'lib/core',
        'data': 'lib/data',
        'domain': 'lib/domain',
        'presentation': 'lib/presentation',
      });
      final deny = {for (final b in a.boundaries) b.from: b.deny};
      expect(deny, {
        'core': ['presentation'],
        'data': ['presentation'],
        'domain': ['data', 'presentation'],
      });
    });

    test('is deterministic', () {
      for (final d in ['services', 'features', 'core']) {
        _dart(root, d);
      }
      final a = LayerDetector.detect(root.path);
      final b = LayerDetector.detect(root.path);
      expect(a.layers, b.layers);
      expect(a.boundaries, b.boundaries);
    });

    test('prefers no layers over doubtful ones', () {
      _dart(root, 'core');
      _dart(root, 'router');
      expect(LayerDetector.detect(root.path).isEmpty, isTrue);
    });

    test('layers of the same tier yield no boundary, so nothing', () {
      _dart(root, 'core');
      _dart(root, 'shared');
      expect(LayerDetector.detect(root.path).isEmpty, isTrue);
    });

    test('ignores a layer directory without Dart files', () {
      _dart(root, 'core');
      Directory(p.join(root.path, 'lib', 'features')).createSync();
      expect(LayerDetector.detect(root.path).isEmpty, isTrue);
    });
  });

  group('loam init materialises layers', () {
    test('writes a block that the config loader reads back', () async {
      for (final d in ['core', 'features']) {
        _dart(root, d);
      }
      expect(await cli.run(['init', '--project-root', root.path]), 0);

      final config = await ConfigLoader.load(root.path);
      expect(config.layers, {'core': 'lib/core', 'features': 'lib/features'});
      expect(config.boundaries.single.from, 'core');
      expect(config.boundaries.single.deny, ['features']);
    });

    test(
      'a hand-edited loam.yaml is never overwritten or re-detected',
      () async {
        for (final d in ['core', 'features']) {
          _dart(root, d);
        }
        final file = File(p.join(root.path, ConfigLoader.fileName))
          ..writeAsStringSync('layers:\n  core: lib/core\n');
        expect(await cli.run(['init', '--project-root', root.path]), 1);

        expect(file.readAsStringSync(), 'layers:\n  core: lib/core\n');
        final config = await ConfigLoader.load(root.path);
        expect(config.layers, {'core': 'lib/core'});
        expect(config.boundaries, isEmpty);
      },
    );

    test('without detection the scaffold is unchanged', () {
      expect(
        ConfigScaffold.generate(
          architecture: const DetectedArchitecture.none(),
        ),
        ConfigScaffold.generate(),
      );
    });
  });

  group('layers config validation', () {
    Future<void> load(String yaml) async {
      File(p.join(root.path, ConfigLoader.fileName)).writeAsStringSync(yaml);
      await ConfigLoader.load(root.path);
    }

    test('rejects a boundary naming an unknown layer', () {
      expect(
        load(
          'layers:\n  core: lib/core\nboundaries:\n'
          '  - from: core\n    deny: [ui]\n',
        ),
        throwsA(isA<ConfigLoadException>()),
      );
    });

    test('normalises Windows separators in layer directories', () async {
      File(p.join(root.path, ConfigLoader.fileName)).writeAsStringSync(
        'layers:\n  core: lib\\core\n  ui: lib\\ui\nboundaries:\n'
        '  - from: core\n    deny: [ui]\n',
      );
      final config = await ConfigLoader.load(root.path);
      expect(config.layers, {'core': 'lib/core', 'ui': 'lib/ui'});
    });

    test(
      'nested configs merge layers per name and boundaries per from',
      () async {
        Directory(p.join(root.path, '.git')).createSync();
        File(p.join(root.path, ConfigLoader.fileName)).writeAsStringSync(
          'layers:\n  core: lib/core\n  ui: lib/ui\n  data: lib/data\n'
          'boundaries:\n  - from: core\n    deny: [ui]\n'
          '  - from: data\n    deny: [ui]\n',
        );
        final pkg = Directory(p.join(root.path, 'pkg'))..createSync();
        File(p.join(pkg.path, ConfigLoader.fileName)).writeAsStringSync(
          'layers:\n  ui: pkg/ui\n'
          'boundaries:\n  - from: core\n    deny: [data]\n',
        );
        final config = await ConfigLoader.load(pkg.path);
        expect(config.layers, {
          'core': 'lib/core',
          'ui': 'pkg/ui',
          'data': 'lib/data',
        });
        final deny = {for (final b in config.boundaries) b.from: b.deny};
        expect(deny, {
          'core': ['data'],
          'data': ['ui'],
        });
      },
    );

    test('rejects a malformed boundary entry', () {
      expect(
        load('layers:\n  core: lib/core\nboundaries:\n  - from: core\n'),
        throwsA(isA<ConfigLoadException>()),
      );
    });
  });
}

@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/config/architecture_config.dart';
import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/finding.dart';
import 'package:loam/src/rules/architecture_boundaries_rule.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture_packages.dart';
import '../support/shared_store.dart';

const _layers = {
  'core': 'lib/core',
  'services': 'lib/services',
  'features': 'lib/features',
};

const _defaultBoundaries = [
  LayerBoundary(from: 'core', deny: ['features']),
  LayerBoundary(from: 'services', deny: ['features']),
];

void main() {
  useSharedAnalyzerStore();

  final fixturePath = p.normalize(
    p.join(Directory.current.path, 'test', 'fixtures', 'boundaries_fixture'),
  );

  late ProjectLoadResult loadResult;

  setUpAll(() async {
    await ensureFixtureResolved(fixturePath);
    loadResult = await ProjectLoader().load(fixturePath);
    expect(loadResult.errors, isEmpty, reason: 'Fixture must load cleanly');
  });

  List<Finding> runRule({
    Map<String, String> layers = _layers,
    List<LayerBoundary> boundaries = _defaultBoundaries,
  }) => ArchitectureBoundariesRule(
    projectRoot: fixturePath,
    layers: layers,
    boundaries: boundaries,
  ).run(loadResult);

  test('reports forbidden edges and none of the allowed ones', () {
    final findings = runRule();
    final edges = {for (final f in findings) '${f.filePath}:${f.line}'};
    expect(edges, {
      'lib/core/leaky.dart:2',
      'lib/core/suppressed.dart:2',
      'lib/services/uses_core_and_features.dart:2',
    });
  });

  test('finding names source layer, target layer, both files and a remedy', () {
    final f = runRule().firstWhere((f) => f.filePath == 'lib/core/leaky.dart');
    expect(f.message, contains('"core"'));
    expect(f.message, contains('"features"'));
    expect(f.message, contains('lib/features/home.dart'));
    expect(f.kind, 'layer-boundary-violation');
    expect(f.remedy, isNotEmpty);
    expect(f.severity, Severity.warning);
  });

  test('fingerprints are unique per forbidden edge', () {
    final prints = runRule().map((f) => f.fingerprint).toList();
    expect(prints.toSet(), hasLength(prints.length));
  });

  test('without boundaries or layers the rule reports nothing', () {
    expect(runRule(boundaries: const []), isEmpty);
    expect(runRule(layers: const {}), isEmpty);
  });

  test('the configured boundaries decide, not a built-in layer model', () {
    final findings = runRule(
      boundaries: const [
        LayerBoundary(from: 'features', deny: ['core']),
      ],
    );
    expect(findings.map((f) => '${f.filePath}:${f.line}'), [
      'lib/features/home.dart:1',
    ]);
    expect(findings.single.message, contains('"features"'));
    expect(findings.single.message, contains('"core"'));
  });

  test('a file belongs to the layer with the longest matching directory', () {
    final findings = runRule(
      layers: const {
        'core': 'lib/core',
        'core-leaky': 'lib/core/leaky.dart',
        'features': 'lib/features',
      },
      boundaries: const [
        LayerBoundary(from: 'core', deny: ['features']),
      ],
    );
    expect(findings.map((f) => f.filePath), ['lib/core/suppressed.dart']);
  });

  test('a layer directory only matches whole path segments', () {
    final findings = runRule(
      layers: const {'partial': 'lib/co', 'features': 'lib/features'},
      boundaries: const [
        LayerBoundary(from: 'partial', deny: ['features']),
      ],
    );
    expect(findings, isEmpty);
  });

  group('through the pipeline', () {
    List<Finding> runPipeline(LoamConfig config) =>
        AnalysisRunner(config: config).runWithLoadResult(
          fixturePath,
          loadResult,
        )..removeWhere((f) => f.ruleId != 'architecture-boundaries');

    const config = LoamConfig(
      ruleToggles: {},
      ignoreGlobs: [],
      layers: _layers,
      boundaries: _defaultBoundaries,
    );

    test(
      'reads layers and boundaries from LoamConfig; inline ignore applies',
      () {
        final files = runPipeline(config).map((f) => f.filePath).toList();
        expect(files, [
          'lib/core/leaky.dart',
          'lib/services/uses_core_and_features.dart',
        ]);
      },
    );

    test('is inert in a zero-config run', () {
      expect(runPipeline(const LoamConfig.defaults()), isEmpty);
    });

    test('can be switched off in loam.yaml', () {
      const off = LoamConfig(
        ruleToggles: {'architecture-boundaries': false},
        ignoreGlobs: [],
        layers: _layers,
        boundaries: _defaultBoundaries,
      );
      expect(runPipeline(off), isEmpty);
    });
  });
}

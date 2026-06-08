@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/rules/import_graph.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Fixture path
// ---------------------------------------------------------------------------

String get _fixturePath => p.normalize(
  p.join(Directory.current.path, 'test', 'fixtures', 'circular_deps_fixture'),
);

// ---------------------------------------------------------------------------
// Shared setup
// ---------------------------------------------------------------------------

void main() {
  late ProjectLoadResult loadResult;
  late ImportGraph graph;

  setUpAll(() async {
    final loader = ProjectLoader();
    loadResult = await loader.load(_fixturePath);
    // The fixture must load without errors (part files and generated files are
    // expected to be excluded by the loader — they appear in errors or are
    // routed to partUnits, not to resolved).
    expect(
      loadResult.errors,
      isEmpty,
      reason:
          'circular_deps_fixture must load cleanly; errors: ${loadResult.errors}',
    );
    graph = ImportGraph.build(loadResult, _fixturePath);
  });

  // ---------------------------------------------------------------------------
  // AC1 — nodes are relative POSIX paths of lib/ files, sorted
  // ---------------------------------------------------------------------------
  group('nodes', () {
    test('contains all non-generated, non-part lib/ files', () {
      expect(graph.nodes, contains('lib/alpha.dart'));
      expect(graph.nodes, contains('lib/beta.dart'));
      expect(graph.nodes, contains('lib/gamma.dart'));
      expect(graph.nodes, contains('lib/delta.dart'));
      expect(graph.nodes, contains('lib/epsilon.dart'));
      expect(graph.nodes, contains('lib/external_user.dart'));
      expect(graph.nodes, contains('lib/codegen_host.dart'));
      expect(graph.nodes, contains('lib/relative_importer.dart'));
    });

    test('nodes are sorted', () {
      final sorted = [...graph.nodes]..sort();
      expect(graph.nodes, equals(sorted));
    });

    // AC3 — generated files excluded
    test('excludes generated files (*.g.dart)', () {
      expect(
        graph.nodes,
        isNot(contains('lib/codegen_host.g.dart')),
        reason: 'generated files must not be nodes',
      );
    });

    // AC4 — part-of files excluded
    test('excludes part-of files', () {
      expect(
        graph.nodes,
        isNot(contains('lib/src/epsilon_part.dart')),
        reason: 'part-of files must not be nodes',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC1 — edges map is keyed by all nodes
  // ---------------------------------------------------------------------------
  group('edges map completeness', () {
    test('every node has an entry in the edges map', () {
      for (final node in graph.nodes) {
        expect(
          graph.edges,
          contains(node),
          reason: 'edges map must have an entry for every node: $node',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // AC2 — import edges on own lib/ libraries
  // ---------------------------------------------------------------------------
  group('import edges', () {
    test('alpha→beta edge exists (package: import)', () {
      expect(
        graph.edges['lib/alpha.dart'],
        contains('lib/beta.dart'),
        reason: 'alpha.dart imports beta.dart via package: URI',
      );
    });

    test('beta→alpha edge exists (completing the cycle)', () {
      expect(
        graph.edges['lib/beta.dart'],
        contains('lib/alpha.dart'),
        reason: 'beta.dart imports alpha.dart back',
      );
    });

    // Relative import edge
    test('relative_importer→delta edge exists (relative import)', () {
      expect(
        graph.edges['lib/relative_importer.dart'],
        contains('lib/delta.dart'),
        reason: 'relative_importer.dart imports delta.dart via relative path',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC2 — export edges on own lib/ libraries
  // ---------------------------------------------------------------------------
  group('export edges', () {
    test('gamma→delta edge exists (export directive)', () {
      expect(
        graph.edges['lib/gamma.dart'],
        contains('lib/delta.dart'),
        reason: 'gamma.dart re-exports delta.dart',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC3 — external packages and dart: produce no edges
  // ---------------------------------------------------------------------------
  group('external imports — no edges', () {
    test('external_user has no outgoing edges (only dart:math import)', () {
      expect(
        graph.edges['lib/external_user.dart'],
        isEmpty,
        reason: 'dart: imports must not create edges',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // AC5 — no self-edges
  // ---------------------------------------------------------------------------
  group('no self-edges', () {
    test('no node appears in its own edge set', () {
      for (final node in graph.nodes) {
        expect(
          graph.edges[node],
          isNot(contains(node)),
          reason: '$node must not have a self-edge',
        );
      }
    });
  });

  // ---------------------------------------------------------------------------
  // AC7 — determinism: two builds of the same result yield identical output
  // ---------------------------------------------------------------------------
  group('determinism', () {
    test('building the graph twice yields identical nodes and edges', () {
      final graph2 = ImportGraph.build(loadResult, _fixturePath);
      expect(graph2.nodes, equals(graph.nodes));
      expect(
        graph2.edges.keys.toList()..sort(),
        equals(graph.edges.keys.toList()..sort()),
      );
      for (final node in graph.nodes) {
        expect(graph2.edges[node], equals(graph.edges[node]));
      }
    });
  });

  // ---------------------------------------------------------------------------
  // AC6 — robustness: no crash on empty / error-only load results
  // ---------------------------------------------------------------------------
  group('robustness', () {
    test('empty ProjectLoadResult does not crash', () {
      const emptyResult = ProjectLoadResult(resolved: [], errors: []);
      final emptyGraph = ImportGraph.build(emptyResult, _fixturePath);
      expect(emptyGraph.nodes, isEmpty);
      expect(emptyGraph.edges, isEmpty);
    });

    test('load result with only errors does not crash', () {
      final errorResult = ProjectLoadResult(
        resolved: const [],
        errors: [
          const LoadFileError(path: '/fake/lib/broken.dart', reason: 'broken'),
        ],
      );
      final errorGraph = ImportGraph.build(errorResult, _fixturePath);
      expect(errorGraph.nodes, isEmpty);
      expect(errorGraph.edges, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // Shape check: edges map is compatible with CycleDetector input format
  // ---------------------------------------------------------------------------
  group('CycleDetector compatibility', () {
    test('edges is Map<String, Set<String>> with all node keys present', () {
      // CycleDetector expects Map<String, Set<String>>.  Verify the types are
      // as expected by checking the runtime type of a few entries.
      for (final node in graph.nodes) {
        final edgeSet = graph.edges[node];
        expect(edgeSet, isA<Set<String>>());
      }
    });
  });
}

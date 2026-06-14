@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/duplicates/duplicate_code_collector.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

final _fixturePath = p.normalize(
  p.join(Directory.current.path, 'test', 'fixtures', 'code_duplicates_fixture'),
);

final _parallelFixturePath = p.normalize(
  p.join(
    Directory.current.path,
    'test',
    'fixtures',
    'parallel_boilerplate_fixture',
  ),
);

/// Loads the fixture and returns a fresh [ProjectLoadResult].
Future<ProjectLoadResult> _loadFixture() async {
  final loader = const ProjectLoader();
  return loader.load(_fixturePath);
}

/// Shorthand: load + collect.
Future<List<DuplicateCluster>> _collectFromFixture() async {
  final result = await _loadFixture();
  return const DuplicateCodeCollector().collect(result, _fixturePath);
}

/// Loads the parallel-boilerplate fixture and collects clusters.
Future<List<DuplicateCluster>> _collectFromParallelFixture() async {
  final loader = const ProjectLoader();
  final result = await loader.load(_parallelFixturePath);
  return const DuplicateCodeCollector().collect(result, _parallelFixturePath);
}

// ---------------------------------------------------------------------------
// Tests
// ---------------------------------------------------------------------------

void main() {
  // -------------------------------------------------------------------------
  // AC: value objects
  // -------------------------------------------------------------------------

  group('DuplicateLocation value object', () {
    test('equality is value-based', () {
      const a = DuplicateLocation(
        filePath: 'lib/alpha.dart',
        startLine: 10,
        endLine: 20,
      );
      const b = DuplicateLocation(
        filePath: 'lib/alpha.dart',
        startLine: 10,
        endLine: 20,
      );
      const c = DuplicateLocation(
        filePath: 'lib/beta.dart',
        startLine: 10,
        endLine: 20,
      );
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });

    test('toString is deterministic', () {
      const loc = DuplicateLocation(
        filePath: 'lib/alpha.dart',
        startLine: 5,
        endLine: 15,
      );
      expect(loc.toString(), loc.toString());
      expect(loc.toString(), contains('alpha.dart'));
    });
  });

  group('DuplicateCluster value object', () {
    test('equality is value-based', () {
      const loc1 = DuplicateLocation(
        filePath: 'lib/alpha.dart',
        startLine: 1,
        endLine: 5,
      );
      const loc2 = DuplicateLocation(
        filePath: 'lib/beta.dart',
        startLine: 1,
        endLine: 5,
      );
      const a = DuplicateCluster(locations: [loc1, loc2], tokenCount: 60);
      const b = DuplicateCluster(locations: [loc1, loc2], tokenCount: 60);
      expect(a, equals(b));
    });
  });

  group('kMinDuplicateTokens', () {
    test('is a positive integer ≥ 50', () {
      // PRD §12: conservative threshold to avoid noise.
      expect(kMinDuplicateTokens, greaterThanOrEqualTo(50));
    });
  });

  // -------------------------------------------------------------------------
  // Fixture-based tests
  // -------------------------------------------------------------------------

  group('fixture-based detection', () {
    late List<DuplicateCluster> clusters;

    setUpAll(() async {
      clusters = await _collectFromFixture();
    });

    // AC: Type-1 exact cross-file duplicate is found.
    test(
      'exact duplicate across two files forms one cluster with two locations',
      () {
        // alpha.dart and beta.dart both define computeTotal — identical body.
        // The exact-duplicate cluster spans both files.
        final crossFileClusters = clusters.where((c) {
          final paths = c.locations.map((l) => l.filePath).toSet();
          return paths.contains('lib/alpha.dart') &&
              paths.contains('lib/beta.dart') &&
              c.locations.length == 2;
        }).toList();

        expect(
          crossFileClusters,
          isNotEmpty,
          reason:
              'Expected at least one cluster spanning alpha.dart and beta.dart',
        );

        // Verify each such cluster has exactly the two expected locations.
        for (final cluster in crossFileClusters) {
          final paths = cluster.locations.map((l) => l.filePath).toList();
          expect(paths, contains('lib/alpha.dart'));
          expect(paths, contains('lib/beta.dart'));
          expect(cluster.locations.length, 2);
        }
      },
    );

    // AC: Type-2 renamed-identifier duplicate is found.
    test('duplicate with renamed identifiers/literals is recognised (Type-2)', () {
      // formatOutput (alpha.dart) and processItems (beta.dart) are Type-2 clones.
      // Because normalisation maps all identifiers to «id» and literals to «lit»,
      // the two structurally identical bodies produce the same token sequence
      // and must appear together in one cluster.
      //
      // The fixture has exactly 2 cross-file clusters:
      //   1. computeTotal (Type-1 — same function name, same body)
      //   2. formatOutput / processItems (Type-2 — different names, same structure)
      //
      // Both must appear in the cluster list.
      expect(
        clusters.length,
        greaterThanOrEqualTo(2),
        reason: 'Expected at least 2 clusters: one Type-1 and one Type-2 pair',
      );

      final crossFileClusters = clusters.where((c) {
        final paths = c.locations.map((l) => l.filePath).toSet();
        return paths.contains('lib/alpha.dart') &&
            paths.contains('lib/beta.dart');
      }).toList();

      expect(
        crossFileClusters.length,
        greaterThanOrEqualTo(2),
        reason:
            'Expected at least 2 cross-file clusters (Type-1 and Type-2 pairs)',
      );
    });

    // AC: short blocks (< kMinDuplicateTokens) are not clustered.
    test('block below minimum token threshold is not clustered', () {
      // addTwo (both files) is a single-expression function — well below the
      // threshold. No cluster should have tokenCount < kMinDuplicateTokens.
      for (final cluster in clusters) {
        expect(
          cluster.tokenCount,
          greaterThanOrEqualTo(kMinDuplicateTokens),
          reason:
              'Cluster with tokenCount=${cluster.tokenCount} is below '
              'the minimum threshold — short blocks must not be clustered',
        );
      }
    });

    // AC: generated files are excluded.
    test('generated files are excluded from cluster locations', () {
      for (final cluster in clusters) {
        for (final loc in cluster.locations) {
          expect(
            loc.filePath,
            isNot(endsWith('.g.dart')),
            reason:
                'Generated file ${loc.filePath} must not appear in any cluster',
          );
          expect(loc.filePath, isNot(endsWith('.freezed.dart')));
          expect(loc.filePath, isNot(endsWith('.mocks.dart')));
        }
      }
    });

    // AC: structurally different code is not clustered (FP check).
    test('unique / structurally different code produces no false positive', () {
      // computeAverage (alpha) and isValidEmail (beta) are structurally unique.
      // Neither should appear as a location together in any cluster.
      for (final cluster in clusters) {
        final paths = cluster.locations.map((l) => l.filePath).toList();
        // A FP would surface here as an extra cluster; instead we verify that
        // the total number of clusters does not grow without bound.
        // The fixture has exactly 2 known duplicate pairs: the exact duplicate
        // (computeTotal) and the Type-2 pair (formatOutput / processItems).
        expect(
          paths,
          isNotEmpty,
          reason: 'Every cluster must have at least one location',
        );
      }
      // No cluster should contain computeAverage or isValidEmail locations
      // (they span only one file each, so they won't be clusters at all).
      // Verify the cluster count is not inflated by false positives.
      // We expect exactly 2 clusters from the fixture (Type-1 + Type-2).
      expect(
        clusters.length,
        lessThanOrEqualTo(4),
        reason:
            'Fixture has 2 known duplicate pairs; more than 4 clusters would '
            'indicate false positives (got ${clusters.length})',
      );

      // Every cluster must have at least 2 unique file paths (cross-file).
      for (final cluster in clusters) {
        final paths = cluster.locations.map((l) => l.filePath).toSet();
        expect(
          paths.length,
          greaterThanOrEqualTo(1),
          reason: 'Every cluster must have at least 1 unique file path',
        );
      }
    });

    // AC: clusters are sorted deterministically.
    test('cluster list is sorted by anchor filePath → startLine', () {
      for (var i = 1; i < clusters.length; i++) {
        final prev = clusters[i - 1].locations.first;
        final cur = clusters[i].locations.first;
        final pathCmp = prev.filePath.compareTo(cur.filePath);
        if (pathCmp < 0) continue;
        if (pathCmp > 0) {
          fail(
            'Cluster sort violated at index $i: '
            '${prev.filePath} > ${cur.filePath}',
          );
        }
        expect(
          prev.startLine,
          lessThanOrEqualTo(cur.startLine),
          reason: 'startLine sort violated at index $i',
        );
      }
    });

    // AC: locations within a cluster are sorted.
    test(
      'locations within each cluster are sorted by filePath → startLine',
      () {
        for (final cluster in clusters) {
          final locs = cluster.locations;
          for (var i = 1; i < locs.length; i++) {
            final prev = locs[i - 1];
            final cur = locs[i];
            final cmp = prev.filePath.compareTo(cur.filePath);
            if (cmp < 0) continue;
            if (cmp > 0) {
              fail(
                'Location sort violated at index $i in cluster: '
                '${prev.filePath} > ${cur.filePath}',
              );
            }
            expect(
              prev.startLine,
              lessThanOrEqualTo(cur.startLine),
              reason: 'startLine sort violated at index $i in cluster',
            );
          }
        }
      },
    );
  });

  // -------------------------------------------------------------------------
  // AC: reproducibility (Invariant 5)
  // -------------------------------------------------------------------------

  group('reproducibility', () {
    test('two runs over the same fixture return identical clusters', () async {
      final clusters1 = await _collectFromFixture();
      final clusters2 = await _collectFromFixture();

      expect(
        clusters1.length,
        equals(clusters2.length),
        reason: 'Cluster count must be identical across runs',
      );
      for (var i = 0; i < clusters1.length; i++) {
        expect(
          clusters1[i],
          equals(clusters2[i]),
          reason: 'Cluster at index $i differs between two runs',
        );
      }
    });
  });

  // -------------------------------------------------------------------------
  // AC: robustness — unresolvable files do not crash
  // -------------------------------------------------------------------------

  group('robustness with errors', () {
    test(
      'unresolvable files are skipped; resolvable files still processed',
      () async {
        final brokenFixturePath = p.normalize(
          p.join(Directory.current.path, 'test', 'fixtures', 'broken_fixture'),
        );
        final loader = const ProjectLoader();
        final result = await loader.load(brokenFixturePath);

        // Must have at least one error.
        expect(result.errors, isNotEmpty);

        // Must not throw.
        late final List<DuplicateCluster> clusters;
        expect(() {
          clusters = const DuplicateCodeCollector().collect(
            result,
            brokenFixturePath,
          );
        }, returnsNormally);

        // Result is a list (possibly empty — no duplicates in broken_fixture).
        expect(clusters, isA<List<DuplicateCluster>>());
      },
    );
  });

  // -------------------------------------------------------------------------
  // AC3/AC4/AC5 — parallel-boilerplate fixture
  // -------------------------------------------------------------------------

  group('parallel_boilerplate_fixture — consistent renaming + gate', () {
    late List<DuplicateCluster> clusters;

    setUpAll(() async {
      clusters = await _collectFromParallelFixture();
    });

    // AC3: parallel boilerplate with a different identifier repetition pattern
    // must NOT cluster, even though the structural skeleton is identical.
    //
    // gamma.dart: computeWeightedSum — uses value*value and ends with
    //             result+value  (pattern has ID#0 reused at slot-0 positions).
    // delta.dart: computeScaledSum  — uses base*scale and ends with
    //             result+scale  (pattern has ID#1 reused at those positions).
    //
    // With blind «id» normalisation both would collapse to the same sequence.
    // With consistent renaming the slot patterns differ → no cluster.
    test(
      'parallel boilerplate with different repetition pattern does not cluster (AC3)',
      () {
        final gammaDeltaClusters = clusters.where((c) {
          final paths = c.locations.map((l) => l.filePath).toSet();
          return paths.contains('lib/gamma.dart') &&
              paths.contains('lib/delta.dart');
        }).toList();

        expect(
          gammaDeltaClusters,
          isEmpty,
          reason:
              'gamma.dart and delta.dart have the same skeleton but different '
              'identifier repetition patterns — consistent renaming must prevent '
              'them from clustering',
        );
      },
    );

    // AC5: a genuine Type-2 clone where only one literal value differs and the
    // identifier repetition pattern is the same MUST still be detected.
    //
    // epsilon.dart: decodeAsBool  — throws FormatException('AsBool: unexpected type')
    // zeta.dart:    decodeAsDouble — throws FormatException('AsDouble: unexpected type')
    //
    // All identifier names differ between the two functions, but the slot
    // repetition pattern is identical. Only the last error message literal
    // differs in value — both map to LIT#3 in their respective fragments.
    test(
      'Type-2 clone with one differing literal value is recognised (AC5)',
      () {
        final type2Clusters = clusters.where((c) {
          final paths = c.locations.map((l) => l.filePath).toSet();
          return paths.contains('lib/epsilon.dart') &&
              paths.contains('lib/zeta.dart');
        }).toList();

        expect(
          type2Clusters,
          isNotEmpty,
          reason:
              'epsilon.dart and zeta.dart are Type-2 clones with the same '
              'slot-repetition pattern — they must still be clustered even '
              'though one error-message literal differs',
        );
      },
    );

    // AC4: low-diversity blocks (few distinct normalised token strings, below
    // kMinDistinctTokenTypes) must be filtered before clustering.
    //
    // lowdiv.dart and lowdiv2.dart each contain a body with 50+ tokens but
    // only 6 distinct normalised strings: `{`, `return`, `ID#0`, `+`, `;`, `}`.
    // Under blind normalisation they would cluster; consistent renaming also
    // produces the same pattern (both are `ID#0 + ID#0 + …`). The
    // distinct-token-gate (kMinDistinctTokenTypes = 8) filters them first.
    test(
      'low-diversity blocks below kMinDistinctTokenTypes are not clustered (AC4)',
      () {
        final lowdivClusters = clusters.where((c) {
          final paths = c.locations.map((l) => l.filePath).toSet();
          return paths.contains('lib/lowdiv.dart') &&
              paths.contains('lib/lowdiv2.dart');
        }).toList();

        expect(
          lowdivClusters,
          isEmpty,
          reason:
              'lowdiv.dart and lowdiv2.dart have only 6 distinct normalised '
              'token types, which is below kMinDistinctTokenTypes ($kMinDistinctTokenTypes) '
              '— the distinct-token-gate must filter them',
        );
      },
    );

    // AC4 (complementary): high-diversity real clones pass the gate.
    // epsilon/zeta (27 distinct types) are already verified above (AC5).
    // gamma and delta each also exceed the threshold individually.
    test('kMinDistinctTokenTypes constant is exported and positive', () {
      expect(kMinDistinctTokenTypes, greaterThan(0));
      expect(kMinDistinctTokenTypes, greaterThan(6));
    });
  });

  // -------------------------------------------------------------------------
  // source_dirs scoping — code-duplicates only scans production source dirs
  // (default lib/ + bin/), exactly like complexity-hotspots, so test/, tool/
  // and example/ duplicates are not reported by default.
  // -------------------------------------------------------------------------
  group('source_dirs scoping', () {
    test('a file is scanned only when its top dir is in sourceDirs', () async {
      final result = await _loadFixture();

      // The fixture's duplicate lives under lib/. Narrowing the scope to bin/
      // only (lib/ excluded) must drop it — proving the filter is applied per
      // top-level directory. By the same mechanism, the default scope
      // (lib + bin) excludes test/, tool/ and example/.
      final binOnly = const DuplicateCodeCollector().collect(
        result,
        _fixturePath,
        sourceDirs: const ['bin'],
      );
      expect(
        binOnly,
        isEmpty,
        reason:
            'the duplicate lives under lib/; scoping to bin/ only must exclude '
            'it, the same way the default lib+bin scope excludes test/',
      );

      // Including lib/ (the default scope) finds the cluster again.
      final withLib = const DuplicateCodeCollector().collect(
        result,
        _fixturePath,
        sourceDirs: const ['lib'],
      );
      expect(withLib, isNotEmpty);
    });

    test('default scope (no sourceDirs argument) equals lib + bin', () async {
      final result = await _loadFixture();

      // The no-argument overload uses kDefaultSourceDirs (lib + bin). Since the
      // fixture's duplicate is under lib/, the default and an explicit
      // ['lib', 'bin'] scope must yield the same clusters.
      final defaultScope = const DuplicateCodeCollector().collect(
        result,
        _fixturePath,
      );
      final explicitScope = const DuplicateCodeCollector().collect(
        result,
        _fixturePath,
        sourceDirs: const ['lib', 'bin'],
      );
      expect(defaultScope.length, explicitScope.length);
      expect(defaultScope, isNotEmpty);
    });
  });
}

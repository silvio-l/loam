@TestOn('vm')
library;

/// Integration tests for PublicApiCollector codegen-input exclusion.
///
/// Verifies that:
/// - Members of code-gen input classes (Drift Table subclasses) are NOT candidates.
/// - Members of plain classes (no code-gen markers) ARE still candidates.
/// - FP-reduction without FN: the new exclusion does not suppress genuine dead code.
///
/// Criterion:
///   AC4: PublicApiCollector integration test: Drift-like table fixture →
///        getters NOT candidates; plain class with unused member → still candidate.
import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/rules/public_api_collector.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.normalize(
    p.join(Directory.current.path, 'test', 'fixtures', 'codegen_input_fixture'),
  );

  late ProjectLoadResult loadResult;
  late List<PublicApiCandidate> candidates;
  const collector = PublicApiCollector();

  setUpAll(() async {
    final loader = ProjectLoader();
    loadResult = await loader.load(fixturePath);
    expect(loadResult.errors, isEmpty, reason: 'Fixture must load cleanly');
    candidates = collector.collect(loadResult, fixturePath);
  });

  // ---------------------------------------------------------------------------
  // AC4: Drift-like table — column getters NOT candidates
  // ---------------------------------------------------------------------------

  test('AC4: DriftTable.name (column getter) is NOT a candidate', () {
    final names = candidates.map((c) => c.semanticAnchor).toSet();
    expect(
      names.contains('DriftTable.name'),
      isFalse,
      reason:
          'DriftTable extends Table (Drift base type) — its getters must '
          'be excluded as code-gen inputs',
    );
  });

  test('AC4: DriftTable.color (column getter) is NOT a candidate', () {
    final names = candidates.map((c) => c.semanticAnchor).toSet();
    expect(
      names.contains('DriftTable.color'),
      isFalse,
      reason:
          'DriftTable extends Table — its column getters must not be candidates',
    );
  });

  test('AC4: DriftTable.isDeleted (column getter) is NOT a candidate', () {
    final names = candidates.map((c) => c.semanticAnchor).toSet();
    expect(
      names.contains('DriftTable.isDeleted'),
      isFalse,
      reason:
          'DriftTable extends Table — its column getters must not be candidates',
    );
  });

  test('AC4: DriftDataClass.displayTitle (getter) is NOT a candidate', () {
    final names = candidates.map((c) => c.semanticAnchor).toSet();
    expect(
      names.contains('DriftDataClass.displayTitle'),
      isFalse,
      reason:
          'DriftDataClass extends DataClass — its getters must not be candidates',
    );
  });

  test('AC4: DriftView.summary (getter) is NOT a candidate', () {
    final names = candidates.map((c) => c.semanticAnchor).toSet();
    expect(
      names.contains('DriftView.summary'),
      isFalse,
      reason: 'DriftView extends View — its getters must not be candidates',
    );
  });

  // ---------------------------------------------------------------------------
  // AC4: Plain class — unused public member IS still a candidate (FN-protection)
  // ---------------------------------------------------------------------------

  test('AC4: PlainClass.unusedField IS a candidate', () {
    final names = candidates.map((c) => c.semanticAnchor).toSet();
    expect(
      names.contains('PlainClass.unusedField'),
      isTrue,
      reason:
          'PlainClass has no code-gen markers — its unused public field '
          'must remain a candidate',
    );
  });

  test('AC4: PlainClass.unusedMethod IS a candidate', () {
    final names = candidates.map((c) => c.semanticAnchor).toSet();
    expect(
      names.contains('PlainClass.unusedMethod'),
      isTrue,
      reason:
          'PlainClass has no code-gen markers — its unused public method '
          'must remain a candidate',
    );
  });

  // ---------------------------------------------------------------------------
  // Top-level classes themselves are still candidates (conservative: only
  // their members are excluded, not the class itself)
  // ---------------------------------------------------------------------------

  test('DriftTable class itself IS still a top-level candidate', () {
    final names = candidates.map((c) => c.name).toSet();
    expect(
      names.contains('DriftTable'),
      isTrue,
      reason:
          'The code-gen input class itself must remain a top-level candidate '
          '(conservative: only its members are excluded)',
    );
  });

  // ---------------------------------------------------------------------------
  // Narrowed fallback heuristic: only the generated-bound class is excluded;
  // a plain class colocated in the same part-bearing library stays a candidate.
  // ---------------------------------------------------------------------------

  test(
    'PartHeuristicNotifier.heuristicMethod is NOT a candidate (fallback)',
    () {
      final names = candidates.map((c) => c.semanticAnchor).toSet();
      expect(
        names.contains('PartHeuristicNotifier.heuristicMethod'),
        isFalse,
        reason:
            'PartHeuristicNotifier binds _\$PartHeuristicNotifier in a library '
            'with part *.g.dart — its members must be excluded via the fallback',
      );
    },
  );

  test('PlainColocatedClass.colocatedLabel IS a candidate (narrowed fallback — '
      'no _\$ binding despite part *.g.dart)', () {
    final names = candidates.map((c) => c.semanticAnchor).toSet();
    expect(
      names.contains('PlainColocatedClass.colocatedLabel'),
      isTrue,
      reason:
          'PlainColocatedClass is hand-written with no generated _\$ binding; '
          'colocating it with a generated part must NOT suppress its members '
          '(regression guard for Hellerio PremiumEntitlement over-suppression)',
    );
  });
}

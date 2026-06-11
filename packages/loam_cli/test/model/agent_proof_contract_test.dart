@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// The agent-proof message contract (hard, deterministic, 0-token).
///
/// Every finding loam emits is consumed by AI agents as well as humans. A
/// finding that states only a bare fact leaves an interpretation gap an agent
/// will fill itself — the root cause of real mis-triage ("those are just
/// build() methods", "that cycle is a standard pattern, not a bug"). To make
/// findings hard to rationalise away, EVERY finding from EVERY live rule must
/// carry:
///   - [Finding.kind]:   a non-empty, machine-readable classifier, and
///   - [Finding.remedy]: a non-empty, concrete next action.
///
/// This test runs the full rule registry against the fixtures that trigger each
/// live rule and asserts the contract holds. A new rule that forgets to set
/// kind/remedy fails here — the contract cannot silently regress.
void main() {
  String fixture(String name) =>
      p.normalize(p.join(Directory.current.path, 'test', 'fixtures', name));

  // Fixtures chosen to exercise every live rule at least once.
  const fixtures = [
    'unused_exports_fixture', // unused-public-exports
    'circular_deps_fixture', // circular-dependencies
    'complexity_hotspots_fixture', // complexity-hotspots
  ];

  test('every finding from every live rule carries kind + remedy', () async {
    final runner = AnalysisRunner();
    final seenRules = <String>{};
    var total = 0;

    for (final name in fixtures) {
      final findings = await runner.run(fixture(name));
      for (final f in findings) {
        total++;
        seenRules.add(f.ruleId);
        expect(
          f.kind,
          isNotNull,
          reason: '${f.ruleId} finding "${f.message}" has null kind',
        );
        expect(
          f.kind,
          isNotEmpty,
          reason: '${f.ruleId} finding "${f.message}" has empty kind',
        );
        expect(
          f.remedy,
          isNotNull,
          reason: '${f.ruleId} finding "${f.message}" has null remedy',
        );
        expect(
          f.remedy,
          isNotEmpty,
          reason: '${f.ruleId} finding "${f.message}" has empty remedy',
        );
      }
    }

    // Guard against a vacuous pass: the fixtures must actually produce findings,
    // and all three live rules must be represented.
    expect(total, greaterThan(0), reason: 'fixtures produced no findings');
    expect(
      seenRules,
      containsAll(<String>{
        'unused-public-exports',
        'circular-dependencies',
        'complexity-hotspots',
      }),
      reason: 'a live rule produced no findings across the fixtures',
    );
  });
}

@TestOn('vm')
library;

import 'dart:io';

import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:loam/src/suppression/suppression_audit.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture_packages.dart';
import '../support/shared_store.dart';

void main() {
  useSharedAnalyzerStore();

  final fixturePath = p.normalize(
    p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'suppression_audit_fixture',
    ),
  );

  Future<AnalysisOutcome> analyzeOn(DateTime today) =>
      AnalysisRunner(clock: () => today).analyze(fixturePath);

  Set<SuppressionNoticeKind> kindsAt(AnalysisOutcome o, int line) => {
    for (final n in o.suppressionAudit.notices)
      if (n.line == line) n.kind,
  };

  Set<String> findingClasses(AnalysisOutcome o) => {
    for (final f in o.findings) f.message,
  };

  group('suppression audit', () {
    late AnalysisOutcome after; // clock after the 2026-01-01 expiry
    late AnalysisOutcome before; // clock before it

    setUpAll(() async {
      await ensureFixtureResolved(fixturePath);
      after = await analyzeOn(DateTime(2026, 11, 3));
      before = await analyzeOn(DateTime(2025, 6, 1));
    });

    test('unused directive is reported, active one is not', () {
      expect(kindsAt(after, 14), {SuppressionNoticeKind.unused});
      expect(kindsAt(after, 2), isEmpty);
    });

    test('directive without reason is reported and suppresses nothing', () {
      expect(kindsAt(after, 18), {SuppressionNoticeKind.missingReason});
      expect(
        after.findings.any(
          (f) => f.filePath == 'lib/audit.dart' && f.line == 19,
        ),
        isTrue,
      );
    });

    test('unknown rule and invalid expiry date are reported', () {
      expect(kindsAt(after, 22), {SuppressionNoticeKind.unknownRule});
      expect(kindsAt(after, 26), {SuppressionNoticeKind.invalidExpiry});
    });

    test('directive without rule ID is reported', () {
      expect(kindsAt(after, 30), {SuppressionNoticeKind.missingRule});
    });

    test(
      'partial run does not flag directives of rules it did not run',
      () async {
        final o = await AnalysisRunner(
          clock: () => DateTime(2026, 11, 3),
          categoryFilter: RuleCategory.accessibility,
        ).analyze(fixturePath);
        final kinds = o.suppressionAudit.notices.map((n) => n.kind).toSet();
        expect(kinds, isNot(contains(SuppressionNoticeKind.unused)));
        expect(o.suppressionAudit.byRule, isEmpty);
      },
    );

    test('expired directive stops suppressing and is reported', () {
      expect(kindsAt(after, 6), {SuppressionNoticeKind.expired});
      expect(
        after.findings.any(
          (f) => f.filePath == 'lib/audit.dart' && f.line == 7,
        ),
        isTrue,
      );
    });

    test('same directive still suppresses before its expiry date', () {
      expect(kindsAt(before, 6), isEmpty);
      expect(
        before.findings.any(
          (f) => f.filePath == 'lib/audit.dart' && f.line == 7,
        ),
        isFalse,
      );
    });

    test('directive is still valid on its last day', () async {
      final lastDay = await analyzeOn(DateTime(2026, 1, 1, 23, 59));
      expect(kindsAt(lastDay, 6), isEmpty);
      final nextDay = await analyzeOn(DateTime(2026, 1, 2));
      expect(kindsAt(nextDay, 6), {SuppressionNoticeKind.expired});
    });

    test('future-dated directive suppresses under both clocks', () {
      for (final o in [before, after]) {
        expect(
          o.findings.any((f) => f.filePath == 'lib/audit.dart' && f.line == 11),
          isFalse,
        );
        expect(kindsAt(o, 10), isEmpty);
      }
    });

    test('until= inside the reason is reported, directive stays valid', () {
      expect(kindsAt(after, 34), {SuppressionNoticeKind.misplacedExpiry});
      expect(
        after.findings.any(
          (f) => f.filePath == 'lib/audit.dart' && f.line == 35,
        ),
        isFalse,
      );
    });

    test('a reasonless loam-ignore is not also a slop-unjustified-ignore', () {
      expect(kindsAt(after, 18), {SuppressionNoticeKind.missingReason});
      expect(
        after.findings.where((f) => f.ruleId == 'slop-unjustified-ignore'),
        isEmpty,
      );
    });

    test('evaluatedOn names the clock day when an expiry is in play', () {
      expect(after.suppressionAudit.evaluatedOn, '2026-11-03');
      expect(before.suppressionAudit.evaluatedOn, '2025-06-01');
    });

    test('counts suppressed findings per rule', () {
      // After expiry: Active + Future + Misplaced are suppressed.
      expect(after.suppressionAudit.byRule, {'unused-public-exports': 3});
      expect(after.suppressedCount, 3);
      // Before expiry: Active + Expired + Future + Misplaced.
      expect(before.suppressionAudit.byRule, {'unused-public-exports': 4});
    });

    test('notices never enter the findings list (warn, do not abort)', () {
      final ruleIds = after.findings.map((f) => f.ruleId).toSet();
      expect(ruleIds, {'unused-public-exports'});
      expect(findingClasses(after), isNotEmpty);
    });

    test('notices are sorted by path, then line', () {
      final lines = after.suppressionAudit.notices.map((n) => n.line).toList();
      expect(lines, [...lines]..sort());
    });
  });
}

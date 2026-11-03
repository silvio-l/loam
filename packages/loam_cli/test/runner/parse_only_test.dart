@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/loader/project_loader.dart';
import 'package:loam/src/model/rule_category.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:loam/src/timing/phase_timer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import '../support/shared_store.dart';

String _describe(AnalysisOutcome outcome) => jsonEncode({
  'findings': [
    for (final f in outcome.findings)
      [f.ruleId, f.filePath, f.line, f.column, f.message, f.fingerprint],
  ],
  'suppressed': outcome.suppressedCount,
  'audit': outcome.suppressionAudit.toJson(),
  'stats': [outcome.stats.filesAnalyzed, outcome.stats.linesAnalyzed],
});

/// Runs [action] with a fresh [PhaseTimer] and returns the recorded labels.
Future<List<String>> _phases(Future<void> Function() action) async {
  final timer = PhaseTimer.active = PhaseTimer(() => Duration.zero);
  try {
    await action();
  } finally {
    PhaseTimer.active = null;
  }
  return [for (final e in timer.entries) e.label];
}

void main() {
  useSharedAnalyzerStore();

  // slop-setstate-after-async-gap, slop-tautological-assertion,
  // slop-undisposed-resource and slop-assertion-free-test read resolved
  // elements (they are plain Rules), so a parse-only slop run needs them
  // switched off.
  const slop = AnalysisRunner(
    config: LoamConfig(
      ruleToggles: {
        'slop-setstate-after-async-gap': false,
        'slop-tautological-assertion': false,
        'slop-undisposed-resource': false,
        'slop-assertion-free-test': false,
      },
      ignoreGlobs: [],
    ),
    categoryFilter: RuleCategory.slop,
  );

  test('a slop-only run parses instead of resolving and reports exactly '
      'what the resolved path reports', () async {
    for (final name in [
      'slop_empty_catch_fixture',
      'slop_narrative_comment_fixture',
      'slop_unjustified_ignore_fixture',
      'slop_workflow_narration_comment_fixture',
      'inline_suppression_fixture',
    ]) {
      final root = p.join(Directory.current.path, 'test', 'fixtures', name);
      late AnalysisOutcome parsed;
      final phases = await _phases(() async {
        parsed = await slop.analyze(root);
      });
      expect(phases, contains('parse'), reason: name);
      expect(phases, isNot(contains('resolve')), reason: name);

      final resolved = slop.analyzeWithLoadResult(
        root,
        await const ProjectLoader().load(root),
      );
      expect(_describe(parsed), _describe(resolved), reason: name);
    }
  });

  test('a run with a non-file rule still resolves', () async {
    final root = p.join(
      Directory.current.path,
      'test',
      'fixtures',
      'unused_exports_fixture',
    );
    final phases = await _phases(() => const AnalysisRunner().analyze(root));
    expect(phases, contains('resolve'));
  });

  test('parse-only also checks files with semantic errors', () async {
    final temp = Directory.systemTemp.createTempSync('loam_parse_only_');
    addTearDown(() => temp.deleteSync(recursive: true));
    File(
      p.join(temp.path, 'pubspec.yaml'),
    ).writeAsStringSync('name: parse_only\nenvironment:\n  sdk: ^3.0.0\n');
    File(p.join(temp.path, 'lib', 'a.dart'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        "import 'package:missing/missing.dart';\n"
        'void f() {\n'
        '  try {\n'
        '    undefinedCall();\n'
        '  } catch (e) {}\n'
        '}\n'
        "const apiKey = 'k8Jx92LmQp4Zr7Tv';\n",
      );
    final outcome = await slop.analyze(temp.path);
    expect(outcome.findings.map((f) => f.ruleId), [
      'slop-empty-catch',
      'hardcoded-secrets',
    ]);
  });
}

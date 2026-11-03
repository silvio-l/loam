@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:loam/src/config/loam_config.dart';
import 'package:loam/src/runner/analysis_runner.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/fixture_packages.dart';
import '../support/shared_store.dart';

/// Copies the fixture package at [source] to [target], rewriting every line
/// break in its Dart files to [eol] (a CRLF checkout on Windows with
/// `core.autocrlf=true` looks exactly like this).
void _copyWithLineEndings(String source, String target, String eol) {
  for (final entity in Directory(source).listSync(recursive: true)) {
    if (entity is! File) continue;
    final rel = p.relative(entity.path, from: source);
    final out = File(p.join(target, rel))..parent.createSync(recursive: true);
    if (rel.endsWith('.dart')) {
      out.writeAsStringSync(
        entity.readAsStringSync().replaceAll(RegExp(r'\r?\n'), eol),
      );
    } else {
      entity.copySync(out.path);
    }
  }
}

String _describe(AnalysisOutcome outcome) =>
    const JsonEncoder.withIndent(' ').convert([
      for (final f in outcome.findings)
        [f.ruleId, f.filePath, f.line, f.column, f.message, f.fingerprint],
    ]);

void main() {
  useSharedAnalyzerStore();

  // Issue #135: a CRLF checkout must yield the same findings — above all the
  // same fingerprints — as an LF one, or a baseline written on macOS/Linux
  // turns the ratchet gate red on Windows.
  test('LF and CRLF checkouts produce identical findings', () async {
    final fixture = await ensureFixtureResolved(
      p.join(
        Directory.current.path,
        'test',
        'fixtures',
        'line_endings_fixture',
      ),
    );
    final tmp = Directory.systemTemp.createTempSync('loam_line_endings_');
    addTearDown(() => tmp.deleteSync(recursive: true));

    const runner = AnalysisRunner(
      config: LoamConfig(ruleToggles: {}, ignoreGlobs: []),
    );
    final results = <String, String>{};
    for (final (name, eol) in [('lf', '\n'), ('crlf', '\r\n')]) {
      final root = p.join(tmp.path, name);
      _copyWithLineEndings(fixture, root, eol);
      results[name] = _describe(await runner.analyze(root));
    }

    // The fixture exercises the source-reading anchors; guard against it
    // silently losing them.
    for (final rule in [
      'a11y-interactive-semantics',
      'slop-empty-catch',
      'slop-narrative-comment',
      'slop-placeholder-comment',
      'slop-unjustified-ignore',
    ]) {
      expect(results['lf'], contains('"$rule"'), reason: rule);
    }
    expect(results['crlf'], results['lf']);
  });
}

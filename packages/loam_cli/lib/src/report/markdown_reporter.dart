import 'package:path/path.dart' as p;

import '../model/finding.dart';
import 'reporter.dart';

/// GitHub-Flavored Markdown reporter.
///
/// Emits a Markdown document with findings grouped by file path, one GFM table
/// per file, and a summary line. Designed to be embedded directly in PR
/// descriptions and documentation surfaces.
///
/// Output structure (with findings):
/// ```markdown
/// ### lib/src/foo.dart
///
/// | Line | Severity | Rule | Message |
/// |------|----------|------|---------|
/// | 10 | warning | unused-public-exports | Unused export: Foo |
///
/// ### lib/src/bar.dart
/// ...
///
/// 3 findings (error: 1, warning: 1, info: 1)  [loam 0.1.2 · ruleset@abc12345]
/// ```
///
/// Or for a clean run:
/// ```markdown
/// 0 findings — clean
/// ```
///
/// Invariant 4 (pure renderer): no I/O, no exit-code logic, no thresholds.
/// Invariant 5 (reproducible): no timestamps, no absolute paths in content;
/// same input always produces a byte-identical string.
class MarkdownReporter implements Reporter {
  /// Creates a [MarkdownReporter].
  const MarkdownReporter();

  @override
  String render(ReportPayload payload) {
    if (payload.findings.isEmpty) {
      return '0 findings — clean\n';
    }

    final buf = StringBuffer();

    // Group findings by filePath while preserving input order.
    final groups = <String, List<Finding>>{};
    for (final f in payload.findings) {
      groups.putIfAbsent(f.filePath, () => []).add(f);
    }

    for (final entry in groups.entries) {
      final rawPath = entry.key;
      // Display paths relative to projectRoot, forward-slash-normalised.
      final filePath = _toRelativePath(rawPath, payload.projectRoot);
      final fileFindings = entry.value;

      // File heading (H3)
      buf.writeln('### $filePath');
      buf.writeln();

      // GFM table header
      buf.writeln('| Line | Severity | Rule | Message |');
      buf.writeln('|------|----------|------|---------|');

      for (final f in fileFindings) {
        final line = f.line.toString();
        final severity = f.severity.name;
        final rule = f.ruleId;
        final message = _escapePipe(f.message);
        buf.writeln('| $line | $severity | $rule | $message |');
      }

      buf.writeln();
    }

    // Summary footer (includes tool/ruleset metadata for traceability).
    buf.write(
      _summaryLine(
        payload.findings,
        payload.toolVersion,
        payload.rulesetVersion,
      ),
    );

    return buf.toString();
  }

  /// Escapes pipe characters in table cell content so GFM tables stay valid.
  String _escapePipe(String text) => text.replaceAll('|', r'\|');

  /// Converts [filePath] to a forward-slash-normalised path relative to
  /// [projectRoot]. Mirrors `JsonReporter._toRelativePath` (Windows safety).
  String _toRelativePath(String filePath, String projectRoot) {
    final rel = p.isAbsolute(filePath)
        ? p.relative(filePath, from: projectRoot)
        : filePath;
    // Normalise to forward slashes (Windows safety) and strip any leading slash.
    final forward = rel.replaceAll(r'\', '/');
    return forward.startsWith('/') ? forward.substring(1) : forward;
  }

  String _summaryLine(
    List<Finding> findings,
    String toolVersion,
    String rulesetVersion,
  ) {
    final total = findings.length;
    final counts = <Severity, int>{};
    for (final f in findings) {
      counts[f.severity] = (counts[f.severity] ?? 0) + 1;
    }

    final breakdown = Severity.values
        .where((s) => (counts[s] ?? 0) > 0)
        .map((s) => '${s.name}: ${counts[s]}')
        .join(', ');

    final suffix = breakdown.isEmpty ? '' : ' ($breakdown)';

    return '$total finding${total == 1 ? '' : 's'}$suffix  '
        '[loam $toolVersion · $rulesetVersion]\n';
  }
}

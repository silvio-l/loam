import 'package:path/path.dart' as p;

import '../model/finding.dart';
import 'reporter.dart';

// ---------------------------------------------------------------------------
// ANSI colour codes (used only when isTty == true)
// ---------------------------------------------------------------------------

const _reset = '\x1B[0m';
const _bold = '\x1B[1m';
const _red = '\x1B[31m';
const _yellow = '\x1B[33m';
const _cyan = '\x1B[36m';
const _grey = '\x1B[90m';

/// Human-readable, grouped terminal reporter.
///
/// Output structure:
/// ```
/// lib/src/foo.dart
///   10      warning  unused-public-exports  Unused export: Foo
///   20:5    error    some-rule              Some message
///
/// lib/src/bar.dart
///   5       info     other-rule             Other message
///
/// 3 findings (error: 1, warning: 1, info: 1)
/// ```
///
/// Or for a clean run:
/// ```
/// 0 findings — clean
/// ```
///
/// ANSI colours are applied only when [ReportPayload.isTty] is `true`;
/// plain text (no escape codes) is emitted otherwise — safe for pipes,
/// logs, and unit tests.
class HumanReporter implements Reporter {
  /// Creates a [HumanReporter].
  const HumanReporter();

  @override
  String render(ReportPayload payload) {
    if (payload.findings.isEmpty) {
      return '0 findings — clean\n';
    }

    final buf = StringBuffer();
    final tty = payload.isTty;

    // Group findings by filePath while preserving input order.
    final groups = <String, List<Finding>>{};
    for (final f in payload.findings) {
      groups.putIfAbsent(f.filePath, () => []).add(f);
    }

    for (final entry in groups.entries) {
      final rawPath = entry.key;
      // Display paths relative to projectRoot for portability.
      final filePath = p.isAbsolute(rawPath)
          ? p.relative(rawPath, from: payload.projectRoot)
          : rawPath;
      final fileFindings = entry.value;

      // File header
      if (tty) {
        buf.writeln('$_bold$filePath$_reset');
      } else {
        buf.writeln(filePath);
      }

      for (final f in fileFindings) {
        final loc = f.column == null ? '${f.line}' : '${f.line}:${f.column}';
        final severityLabel = _severityLabel(f.severity, tty);

        buf.writeln(
          '  ${loc.padRight(8)}$severityLabel  ${f.ruleId}  ${f.message}',
        );
      }

      buf.writeln();
    }

    // Summary footer (includes tool/ruleset metadata for traceability).
    buf.write(
      _summaryLine(
        payload.findings,
        payload.toolVersion,
        payload.rulesetVersion,
        tty,
      ),
    );

    return buf.toString();
  }

  String _severityLabel(Severity severity, bool tty) {
    final label = severity.name; // 'error', 'warning', 'info'
    if (!tty) return label;
    return switch (severity) {
      Severity.error => '$_red$label$_reset',
      Severity.warning => '$_yellow$label$_reset',
      Severity.info => '$_cyan$label$_reset',
    };
  }

  String _summaryLine(
    List<Finding> findings,
    String toolVersion,
    String rulesetVersion,
    bool tty,
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

    // Include tool version and ruleset version for traceability.
    final label =
        '$total finding${total == 1 ? '' : 's'}$suffix  '
        '[loam $toolVersion · $rulesetVersion]';
    if (tty) {
      return '$_grey$label$_reset\n';
    }
    return '$label\n';
  }
}

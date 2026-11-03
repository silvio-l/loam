import '../model/finding.dart';
import 'reporter.dart';

/// Compact, size-bounded reporter for AI agents and chat contexts.
///
/// Lists the highest-impact findings first (severity, then rule, path, line,
/// fingerprint — a total order, so output is deterministic) and cuts the list
/// at [defaultMaxFindings] or [ReportPayload.maxFindings]. The footer always
/// says how many findings were left out and how to see all of them, so a
/// truncated list is never mistaken for a complete one.
///
/// pure renderer, ADR 0001: no I/O, no exit-code logic. Invariant 5: no
/// timestamps, no absolute paths.
class AgentReporter implements Reporter {
  /// Creates an [AgentReporter].
  const AgentReporter();

  /// How many findings are listed when `--max-findings` is not given.
  static const int defaultMaxFindings = 20;

  @override
  String render(ReportPayload payload) {
    final suppressed = payload.suppressedCount > 0
        ? ' (${payload.suppressedCount} suppressed)'
        : '';
    if (payload.findings.isEmpty) return '0 findings — clean$suppressed\n';

    final sorted = sortByImpact(payload.findings);
    final cap = payload.maxFindings ?? defaultMaxFindings;
    final shown = cap <= 0 || cap >= sorted.length
        ? sorted
        : sorted.sublist(0, cap);
    final omitted = sorted.length - shown.length;

    final buf = StringBuffer()
      ..writeln(
        '${sorted.length} finding${sorted.length == 1 ? '' : 's'} '
        '(${_breakdown(sorted)})$suppressed '
        '[loam ${payload.toolVersion} · ${payload.rulesetVersion}]',
      );
    if (omitted > 0) {
      buf.writeln(
        'Showing the ${shown.length} of ${sorted.length} with the highest impact.',
      );
    }
    buf.writeln();

    for (final f in shown) {
      final path = _clean(relativeReportPath(f.filePath, payload.projectRoot));
      buf.writeln(
        '${f.severity.name} ${_clean(f.ruleId)} $path:${f.line} — '
        '${_clean(f.message)}',
      );
      if (f.remedy != null) buf.writeln('  fix: ${_clean(f.remedy!)}');
    }

    if (omitted > 0) {
      buf
        ..writeln()
        ..writeln(
          '$omitted more finding${omitted == 1 ? '' : 's'} omitted '
          '(${_breakdown(sorted.sublist(shown.length))}). '
          'Show all: --max-findings 0 (or --format json / sarif).',
        );
    }
    return buf.toString();
  }

  /// Findings ordered by impact: severity descending, then rule, path, line
  /// and fingerprint ascending. Returns a new list.
  static List<Finding> sortByImpact(List<Finding> findings) {
    return [...findings]..sort((a, b) {
      final bySeverity = b.severity.index.compareTo(a.severity.index);
      if (bySeverity != 0) return bySeverity;
      final byRule = a.ruleId.compareTo(b.ruleId);
      if (byRule != 0) return byRule;
      final byPath = a.filePath.compareTo(b.filePath);
      if (byPath != 0) return byPath;
      final byLine = a.line.compareTo(b.line);
      if (byLine != 0) return byLine;
      return a.fingerprint.compareTo(b.fingerprint);
    });
  }

  /// Neutralises control characters (ESC/ANSI, CR, LF, NUL, C1, bidi
  /// overrides) in text that originates from analysed code, so a message or
  /// path can neither forge extra lines in the list nor drive the terminal or
  /// inject instructions on separate lines of an agent prompt.
  static final _unsafe = RegExp(
    r'[\u0000-\u001F\u007F-\u009F\u2028\u2029\u202A-\u202E\u2066-\u2069]+',
  );
  String _clean(String text) => text.replaceAll(_unsafe, ' ').trim();

  String _breakdown(List<Finding> findings) {
    final counts = <Severity, int>{};
    for (final f in findings) {
      counts[f.severity] = (counts[f.severity] ?? 0) + 1;
    }
    return Severity.values.reversed
        .where((s) => (counts[s] ?? 0) > 0)
        .map((s) => '${s.name}: ${counts[s]}')
        .join(', ');
  }
}

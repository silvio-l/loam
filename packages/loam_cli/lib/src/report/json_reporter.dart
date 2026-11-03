import 'dart:convert';

import 'package:path/path.dart' as p;

import '../model/finding.dart';
import '../recommendation/recommendation_engine.dart';
import 'reporter.dart';

/// Machine-readable JSON reporter.
///
/// Emits a schema-versioned envelope with a metadata block, summary counts,
/// and a `findings` array. Designed as the canonical agent/LLM contract surface.
///
/// Envelope shape (schemaVersion 2):
/// ```json
/// {
///   "schemaVersion": 2,
///   "tool": { "name": "loam", "version": "<toolVersion>" },
///   "ruleset": "<rulesetVersion>",
///   "summary": { "total": N, "error": N, "warning": N, "info": N },
///   "findings": [
///     {
///       "ruleId": "...", "severity": "...", "filePath": "...",
///       "line": N, "column": N, "message": "...", "fingerprint": "...",
///       "kind": "...",   // agent-proof classifier (schemaVersion 2+); may be null
///       "remedy": "..."  // concrete next action  (schemaVersion 2+); may be null
///     }
///   ]
/// }
/// ```
///
/// `schemaVersion` 2 added `kind` and `remedy` (the agent-proof message
/// contract). Consumers reading the structured fields should not parse them out
/// of `message`.
///
/// When [ReportPayload.recommendations] is non-empty, the envelope also gets
/// a top-level `guidanceVersion` (the [kGuidanceVersion] marker) and a
/// `recommendations` array of `{ "ruleId": "...", "guidance": "..." }` — the
/// primary agentic path for preventive guidance (issue 04). Both keys are
/// omitted entirely (not emitted as empty) when there are no recommendations,
/// e.g. a clean (0-findings) run.
///
/// When suppression happened or a `// loam-ignore:` directive needs attention,
/// the envelope has a `suppression` object (omitted otherwise; SARIF carries
/// the same object under `runs[].properties.suppression`):
/// ```json
/// "suppression": {
///   "evaluatedOn": "YYYY-MM-DD",  // only when a directive has `until=`
///   "byRule": { "<ruleId>": N },  // findings suppressed per rule, sorted
///   "notices": [ { "kind": "...", "filePath": "...", "line": N,
///                  "ruleId": "..."|null, "message": "..." } ]
/// }
/// ```
/// `kind` is one of `unused`, `expired`, `missing-reason`, `missing-rule`,
/// `invalid-expiry`, `unknown-rule`, `misplaced-expiry`. All keys are additive:
/// consumers must ignore unknown keys and unknown `kind` values.
/// `evaluatedOn` is the only clock-derived value; it exists because expiry
/// makes the result depend on the day (internal-notes, Invariante 5).
///
/// pure renderer, ADR 0001: no I/O, no exit-code logic, no thresholds.
/// Invariant 5 (reproducible): no timestamps (the date-only `suppression.evaluatedOn` is the
/// one exception), no absolute paths in content;
/// same input always produces a byte-identical string.
class JsonReporter implements Reporter {
  /// Creates a [JsonReporter].
  const JsonReporter();

  @override
  String render(ReportPayload payload) {
    final counts = <Severity, int>{
      Severity.error: 0,
      Severity.warning: 0,
      Severity.info: 0,
    };
    for (final f in payload.findings) {
      counts[f.severity] = (counts[f.severity] ?? 0) + 1;
    }

    final stats = payload.stats;
    final projectName = p.basename(payload.projectRoot);
    final projectBlock = <String, dynamic>{
      'name': projectName,
      if (payload.sourceDirs != null) 'sourceDirs': payload.sourceDirs,
    };
    final doc = <String, dynamic>{
      'schemaVersion': 3,
      'project': projectBlock,
      'tool': {'name': 'loam', 'version': payload.toolVersion},
      'ruleset': payload.rulesetVersion,
      'summary': {
        'total': payload.findings.length,
        'error': counts[Severity.error],
        'warning': counts[Severity.warning],
        'info': counts[Severity.info],
        'suppressed': payload.suppressedCount,
      },
      if (!payload.suppressionAudit.isEmpty)
        'suppression': payload.suppressionAudit.toJson(),
      if (stats != null)
        'scan': {
          'filesAnalyzed': stats.filesAnalyzed,
          'libFilesAnalyzed': stats.libFilesAnalyzed,
          'linesAnalyzed': stats.linesAnalyzed,
          'rulesRun': stats.rulesRun,
        },
      // Primary agentic path for preventive guidance: a structured array
      // (ruleId + guidance), not free text. Omitted entirely (not an empty
      // array) when there are no recommendations, so a clean run's envelope
      // stays free of empty noise.
      if (payload.recommendations.isNotEmpty) ...{
        'guidanceVersion': kGuidanceVersion,
        'recommendations': payload.recommendations
            .map((r) => {'ruleId': r.ruleId, 'guidance': r.guidance})
            .toList(),
      },
      'findings': payload.findings
          .map((f) => _buildFinding(f, payload.projectRoot))
          .toList(),
    };

    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  Map<String, dynamic> _buildFinding(Finding f, String projectRoot) {
    return {
      'ruleId': f.ruleId,
      'severity': f.severity.name, // 'error', 'warning', 'info'
      'filePath': relativeReportPath(f.filePath, projectRoot),
      'line': f.line,
      'column': f.column, // null is serialised as JSON null
      'message': f.message,
      'fingerprint': f.fingerprint,
      'kind': f.kind, // agent-proof classifier; null is serialised as JSON null
      'remedy':
          f.remedy, // concrete next action; null is serialised as JSON null
      // WCAG reference for accessibility findings; omitted entirely when null.
      if (f.wcagRef != null)
        'wcagRef': {
          'number': f.wcagRef!.number,
          'title': f.wcagRef!.title,
          'url': f.wcagRef!.url,
        },
    };
  }
}

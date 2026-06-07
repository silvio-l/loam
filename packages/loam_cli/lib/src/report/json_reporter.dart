import 'dart:convert';

import 'package:path/path.dart' as p;

import '../model/finding.dart';
import 'reporter.dart';

/// Machine-readable JSON reporter.
///
/// Emits a schema-versioned envelope with a metadata block, summary counts,
/// and a `findings` array. Designed as the canonical agent/LLM contract surface.
///
/// Envelope shape (schemaVersion 1):
/// ```json
/// {
///   "schemaVersion": 1,
///   "tool": { "name": "loam", "version": "<toolVersion>" },
///   "ruleset": "<rulesetVersion>",
///   "summary": { "total": N, "error": N, "warning": N, "info": N },
///   "findings": [ ... ]
/// }
/// ```
///
/// Invariant 4 (pure renderer): no I/O, no exit-code logic, no thresholds.
/// Invariant 5 (reproducible): no timestamps, no absolute paths in content;
/// same input always produces a byte-identical string.
class JsonReporter implements Reporter {
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

    final doc = <String, dynamic>{
      'schemaVersion': 1,
      'tool': {'name': 'loam', 'version': payload.toolVersion},
      'ruleset': payload.rulesetVersion,
      'summary': {
        'total': payload.findings.length,
        'error': counts[Severity.error],
        'warning': counts[Severity.warning],
        'info': counts[Severity.info],
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
      'filePath': _toRelativePath(f.filePath, projectRoot),
      'line': f.line,
      'column': f.column, // null is serialised as JSON null
      'message': f.message,
      'fingerprint': f.fingerprint,
    };
  }

  /// Converts [filePath] to a forward-slash-normalised path relative to
  /// [projectRoot]. Mirrors `SarifReporter._toRelativeUri` (Windows safety).
  String _toRelativePath(String filePath, String projectRoot) {
    final rel = p.isAbsolute(filePath)
        ? p.relative(filePath, from: projectRoot)
        : filePath;
    // Normalise to forward slashes (Windows safety) and strip any leading slash.
    final forward = rel.replaceAll(r'\', '/');
    return forward.startsWith('/') ? forward.substring(1) : forward;
  }
}

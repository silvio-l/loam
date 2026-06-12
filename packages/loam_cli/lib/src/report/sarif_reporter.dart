import 'dart:convert';

import 'package:path/path.dart' as p;

import '../model/finding.dart';
import 'reporter.dart';

/// SARIF 2.1.0 reporter.
///
/// Builds the SARIF log as plain Dart [Map]/[List] and serialises via
/// [JsonEncoder.withIndent] from `dart:convert`. No third-party SARIF
/// dependency — handbuilt per the SARIF 2.1.0 spec.
///
/// Invariant 4 (pure renderer): no I/O, no exit-code logic, no thresholds.
/// Invariant 5 (reproducible): no timestamps, no absolute paths in content;
/// same input always produces a byte-identical string.
class SarifReporter implements Reporter {
  /// Creates a [SarifReporter].
  const SarifReporter();

  static const _schemaUri =
      'https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json';

  @override
  String render(ReportPayload payload) {
    // Deduplicated, ordered rules catalog from the findings present.
    final seenRuleIds = <String>{};
    final rulesCatalog = <Map<String, dynamic>>[];
    for (final f in payload.findings) {
      if (seenRuleIds.add(f.ruleId)) {
        rulesCatalog.add({'id': f.ruleId});
      }
    }

    final results = payload.findings
        .map((f) => _buildResult(f, payload.projectRoot))
        .toList();

    final doc = <String, dynamic>{
      r'$schema': _schemaUri,
      'version': '2.1.0',
      'runs': [
        {
          'tool': {
            'driver': {
              'name': 'loam',
              'version': payload.toolVersion,
              'informationUri': 'https://getloam.dev',
              'rules': rulesCatalog,
            },
          },
          'results': results,
          // Run-level property bag: scope + suppression context, so tooling can
          // tell a clean run that covered the codebase from one that scanned
          // little or hid findings. Standards-friendly (`runs[].properties`).
          'properties': {
            'suppressed': payload.suppressedCount,
            if (payload.stats case final stats?) ...{
              'filesAnalyzed': stats.filesAnalyzed,
              'libFilesAnalyzed': stats.libFilesAnalyzed,
              'linesAnalyzed': stats.linesAnalyzed,
              'rulesRun': stats.rulesRun,
            },
          },
        },
      ],
    };

    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  Map<String, dynamic> _buildResult(Finding f, String projectRoot) {
    final uri = _toRelativeUri(f.filePath, projectRoot);
    final region = _buildRegion(f);

    return {
      'ruleId': f.ruleId,
      'level': _levelFor(f.severity),
      'message': {'text': f.message},
      'locations': [
        {
          'physicalLocation': {
            'artifactLocation': {'uri': uri},
            'region': region,
          },
        },
      ],
      // Agent-proof message contract: expose the classifier and concrete next
      // action in the SARIF property bag so tooling/agents read structure, not
      // prose. Omitted entirely when absent (no null keys).
      if (f.kind != null || f.remedy != null)
        'properties': {
          if (f.kind != null) 'kind': f.kind,
          if (f.remedy != null) 'remedy': f.remedy,
        },
    };
  }

  /// Converts [filePath] to a forward-slash-normalised, no-leading-slash URI
  /// relative to [projectRoot].
  String _toRelativeUri(String filePath, String projectRoot) {
    final rel = p.isAbsolute(filePath)
        ? p.relative(filePath, from: projectRoot)
        : filePath;
    // Normalise to forward slashes (Windows safety) and strip any leading slash.
    final forward = rel.replaceAll(r'\', '/');
    return forward.startsWith('/') ? forward.substring(1) : forward;
  }

  Map<String, dynamic> _buildRegion(Finding f) {
    final region = <String, dynamic>{'startLine': f.line};
    if (f.column != null) {
      region['startColumn'] = f.column;
    }
    return region;
  }

  /// Maps [Severity] to the SARIF `level` string.
  ///
  /// - [Severity.error]   → `"error"`
  /// - [Severity.warning] → `"warning"`
  /// - [Severity.info]    → `"note"`
  String _levelFor(Severity severity) => switch (severity) {
    Severity.error => 'error',
    Severity.warning => 'warning',
    Severity.info => 'note',
  };
}

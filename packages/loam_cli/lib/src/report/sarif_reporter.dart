import 'dart:convert';

import 'package:path/path.dart' as p;

import '../baseline/baseline.dart';
import '../model/finding.dart';
import '../recommendation/recommendation_engine.dart';
import 'reporter.dart';

/// SARIF 2.1.0 reporter.
///
/// Builds the SARIF log as plain Dart [Map]/[List] and serialises via
/// [JsonEncoder.withIndent] from `dart:convert`. No third-party SARIF
/// dependency — handbuilt per the SARIF 2.1.0 spec.
///
/// pure renderer, ADR 0001: no I/O, no exit-code logic, no thresholds.
/// Invariant 5 (reproducible): no timestamps, no absolute paths in content;
/// same input always produces a byte-identical string.
class SarifReporter implements Reporter {
  /// Creates a [SarifReporter].
  const SarifReporter();

  static const _schemaUri =
      'https://docs.oasis-open.org/sarif/sarif/v2.1.0/errata01/os/schemas/sarif-schema-2.1.0.json';

  @override
  String render(ReportPayload payload) {
    // Rules catalog: one entry per rule present (findings or, with a baseline
    // diff, fixed entries), sorted by id so the catalog and every result's
    // `ruleIndex` are deterministic.
    final ruleIds = <String>{
      for (final f in payload.findings) f.ruleId,
      for (final f
          in payload.baselineDiff?.fixedFindings ?? const <BaselineFinding>[])
        f.ruleId,
    }.toList()..sort();
    final ruleIndex = {for (var i = 0; i < ruleIds.length; i++) ruleIds[i]: i};
    final worst = <String, Severity>{};
    for (final f in payload.findings) {
      final cur = worst[f.ruleId];
      if (cur == null || f.severity.index > cur.index) {
        worst[f.ruleId] = f.severity;
      }
    }
    final rulesCatalog = [for (final id in ruleIds) _buildRule(id, worst[id])];

    final diff = payload.baselineDiff;
    final keptFingerprints = {
      for (final f in diff?.keptFindings ?? const <Finding>[]) f.fingerprint,
    };
    final results = <Map<String, dynamic>>[
      for (final f in payload.findings)
        _buildResult(
          f,
          payload.projectRoot,
          ruleIndex[f.ruleId]!,
          diff == null
              ? null
              : (keptFingerprints.contains(f.fingerprint)
                    ? 'unchanged'
                    : 'new'),
        ),
      // Baseline entries that no longer occur: reported as `absent` so a
      // code-scanning system can close them.
      if (diff != null)
        for (final f in diff.fixedFindings)
          {
            'ruleId': f.ruleId,
            'ruleIndex': ruleIndex[f.ruleId],
            'level': 'none',
            'message': {'text': f.message},
            'locations': [
              {
                'physicalLocation': {
                  'artifactLocation': {
                    'uri': relativeReportPath(f.filePath, payload.projectRoot),
                  },
                  'region': {'startLine': f.line},
                },
              },
            ],
            'partialFingerprints': {_fingerprintKey: f.fingerprint},
            'baselineState': 'absent',
          },
    ];

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
          // Run-level property bag: repo identity, scope + suppression context,
          // so tooling can tell a clean run that covered the codebase from one
          // that scanned little or hid findings. Standards-friendly
          // (`runs[].properties`). Invariant 5: only basename, no absolute path.
          'properties': {
            'projectName': p.basename(payload.projectRoot),
            if (payload.sourceDirs != null) 'sourceDirs': payload.sourceDirs,
            'suppressed': payload.suppressedCount,
            if (!payload.suppressionAudit.isEmpty)
              'suppression': payload.suppressionAudit.toJson(),
            if (payload.stats case final stats?) ...{
              'filesAnalyzed': stats.filesAnalyzed,
              'libFilesAnalyzed': stats.libFilesAnalyzed,
              'linesAnalyzed': stats.linesAnalyzed,
              'rulesRun': stats.rulesRun,
            },
            // Preventive recommendations (issue 04): curated, deduplicated
            // guidance for the rule classes that fired, keyed by ruleId.
            // Omitted entirely when there are none (clean run).
            if (payload.recommendations.isNotEmpty) ...{
              'guidanceVersion': kGuidanceVersion,
              'recommendations': payload.recommendations
                  .map((r) => {'ruleId': r.ruleId, 'guidance': r.guidance})
                  .toList(),
            },
          },
        },
      ],
    };

    return const JsonEncoder.withIndent('  ').convert(doc);
  }

  /// Stable key for [Finding.fingerprint] in `partialFingerprints`. The suffix
  /// versions the hashing scheme (see `computeFingerprint`).
  static const _fingerprintKey = 'loamFingerprint/v1';

  Map<String, dynamic> _buildRule(String id, Severity? worstSeverity) {
    final guidance = kGuidanceCorpus[id];
    return {
      'id': id,
      'name': id,
      'shortDescription': {'text': id},
      'help': {
        'text':
            guidance ?? 'See the loam.dev documentation for the rule `$id`.',
      },
      'defaultConfiguration': ?(worstSeverity == null
          ? null
          : {'level': _levelFor(worstSeverity)}),
    };
  }

  Map<String, dynamic> _buildResult(
    Finding f,
    String projectRoot,
    int ruleIndex,
    String? baselineState,
  ) {
    final uri = relativeReportPath(f.filePath, projectRoot);
    final region = _buildRegion(f);

    return {
      'ruleId': f.ruleId,
      'ruleIndex': ruleIndex,
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
      'partialFingerprints': {_fingerprintKey: f.fingerprint},
      'baselineState': ?baselineState,
      // Agent-proof message contract: expose the classifier, concrete next
      // action, and WCAG reference in the SARIF property bag so tooling/agents
      // read structure, not prose. Omitted entirely when all absent (no null keys).
      if (f.kind != null || f.remedy != null || f.wcagRef != null)
        'properties': {
          if (f.kind != null) 'kind': f.kind,
          if (f.remedy != null) 'remedy': f.remedy,
          if (f.wcagRef != null)
            'wcagRef': {
              'number': f.wcagRef!.number,
              'title': f.wcagRef!.title,
              'url': f.wcagRef!.url,
            },
        },
    };
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

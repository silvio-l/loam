import 'dart:convert';
import 'dart:io';

import '../model/finding.dart';
import 'baseline.dart';
import 'baseline_diff.dart';

export 'baseline.dart';
export 'baseline_diff.dart';

/// Current schema version for `baseline.json`.
///
/// Increment only on breaking schema changes. New optional top-level fields
/// (e.g. `promptVersion`) are added additively without a version bump (D8).
const _kSchemaVersion = 1;

/// Thrown by [BaselineEngine.read] when `baseline.json` is missing,
/// corrupt, or has an unrecognisable schema.
///
/// Always carries a human-readable [message] — no raw stack traces bubble up.
class BaselineException implements Exception {
  const BaselineException(this.message);

  final String message;

  @override
  String toString() => 'BaselineException: $message';
}

/// Serialises and deserialises the `baseline.json` file.
///
/// The baseline freezes the *accepted* finding state so that the ratchet gate
/// ([GateEngine], Slice 04) can diff subsequent runs against it.
///
/// **Location:** `<projectRoot>/baseline.json` — same directory as the
/// `pubspec.yaml` of the analysed project.
///
/// **Schema** (JSON, top-level object):
/// ```json
/// {
///   "schemaVersion": 1,
///   "rulesetVersion": "ruleset@abc123",
///   "findings": [
///     {
///       "fingerprint": "abc123def456abcd",
///       "ruleId":      "unused-public-exports",
///       "filePath":    "lib/src/foo.dart",
///       "line":        10,
///       "message":     "Unused export: Foo"
///     }
///   ]
/// }
/// ```
///
/// Findings are stably sorted (filePath → line → fingerprint) so that
/// `baseline.json` is deterministic and produces clean git diffs.
class BaselineEngine {
  const BaselineEngine({required this.projectRoot});

  /// Root directory of the analysed project; `baseline.json` is written here.
  final String projectRoot;

  /// Path to `baseline.json` inside [projectRoot].
  String get baselinePath => '$projectRoot/baseline.json';

  /// Whether `baseline.json` currently exists.
  bool get exists => File(baselinePath).existsSync();

  // ---------------------------------------------------------------------------
  // Write
  // ---------------------------------------------------------------------------

  /// Writes [findings] to `baseline.json` under [projectRoot].
  ///
  /// Findings are sorted deterministically (filePath → line → fingerprint)
  /// before serialisation — regardless of the order they arrive in.
  ///
  /// [rulesetVersion] is written verbatim; derive it via
  /// [AnalysisRunner.rulesetVersion] to stay in sync with the active rule set.
  void write(List<Finding> findings, String rulesetVersion) {
    final sorted = List<Finding>.from(findings)
      ..sort((a, b) {
        final pathCmp = a.filePath.compareTo(b.filePath);
        if (pathCmp != 0) return pathCmp;
        final lineCmp = a.line.compareTo(b.line);
        if (lineCmp != 0) return lineCmp;
        return a.fingerprint.compareTo(b.fingerprint);
      });

    final json = <String, Object>{
      'schemaVersion': _kSchemaVersion,
      'rulesetVersion': rulesetVersion,
      'findings': sorted
          .map(
            (f) => <String, Object>{
              'fingerprint': f.fingerprint,
              'ruleId': f.ruleId,
              'filePath': f.filePath,
              'line': f.line,
              'message': f.message,
            },
          )
          .toList(),
    };

    // Pretty-print with 2-space indentation so each finding occupies ~one line
    // in git diffs, which improves reviewability.
    final encoder = JsonEncoder.withIndent('  ');
    File(baselinePath).writeAsStringSync('${encoder.convert(json)}\n');
  }

  // ---------------------------------------------------------------------------
  // Diff
  // ---------------------------------------------------------------------------

  /// Compares [current] findings against the frozen [baseline] using
  /// **fingerprint-only** set arithmetic (Invariant 3).
  ///
  /// - `newFindings`   = current ∖ baseline  (fail the ratchet gate)
  /// - `keptFindings`  = current ∩ baseline  (legacy; never fail)
  /// - `fixedFindings` = baseline ∖ current  (improvements; never fail)
  ///
  /// A pure line-shift is transparent: the fingerprint stays the same → kept.
  BaselineDiff diff(List<Finding> current, Baseline baseline) {
    final baselineFingerprints = {
      for (final f in baseline.findings) f.fingerprint: f,
    };
    final currentFingerprints = {for (final f in current) f.fingerprint};

    final newFindings = <Finding>[];
    final keptFindings = <Finding>[];
    for (final f in current) {
      if (baselineFingerprints.containsKey(f.fingerprint)) {
        keptFindings.add(f);
      } else {
        newFindings.add(f);
      }
    }

    final fixedFindings = <BaselineFinding>[];
    for (final bf in baseline.findings) {
      if (!currentFingerprints.contains(bf.fingerprint)) {
        fixedFindings.add(bf);
      }
    }

    return BaselineDiff(
      newFindings: newFindings,
      keptFindings: keptFindings,
      fixedFindings: fixedFindings,
    );
  }

  // ---------------------------------------------------------------------------
  // Read
  // ---------------------------------------------------------------------------

  /// Reads and parses `baseline.json` from [projectRoot].
  ///
  /// Throws [BaselineException] with a clear message if the file is:
  /// - missing
  /// - not valid JSON
  /// - missing required top-level fields (`schemaVersion`, `rulesetVersion`,
  ///   `findings`)
  ///
  /// Never throws raw [FormatException] or [FileSystemException].
  Baseline read() {
    final file = File(baselinePath);

    if (!file.existsSync()) {
      throw const BaselineException(
        'baseline.json is missing. '
        'Run `loam baseline --write` to create one.',
      );
    }

    final raw = file.readAsStringSync();
    Map<String, dynamic> json;
    try {
      json = jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException catch (e) {
      throw BaselineException(
        'baseline.json is corrupt and could not be parsed: ${e.message}. '
        'Re-create it with `loam baseline --write`.',
      );
    } on TypeError {
      throw const BaselineException(
        'baseline.json has an invalid structure (not a JSON object). '
        'Re-create it with `loam baseline --write`.',
      );
    }

    // Validate required top-level fields.
    if (json['schemaVersion'] is! int ||
        json['rulesetVersion'] is! String ||
        json['findings'] is! List) {
      throw const BaselineException(
        'baseline.json is missing required fields '
        '(schemaVersion, rulesetVersion, findings). '
        'Re-create it with `loam baseline --write`.',
      );
    }

    final rawFindings = json['findings'] as List<dynamic>;
    final findings = <BaselineFinding>[];
    for (final entry in rawFindings) {
      if (entry is! Map<String, dynamic>) {
        throw const BaselineException(
          'baseline.json contains an invalid finding entry. '
          'Re-create it with `loam baseline --write`.',
        );
      }
      findings.add(
        BaselineFinding(
          fingerprint: entry['fingerprint'] as String? ?? '',
          ruleId: entry['ruleId'] as String? ?? '',
          filePath: entry['filePath'] as String? ?? '',
          line: entry['line'] as int? ?? 0,
          message: entry['message'] as String? ?? '',
        ),
      );
    }

    return Baseline(
      schemaVersion: json['schemaVersion'] as int,
      rulesetVersion: json['rulesetVersion'] as String,
      findings: findings,
    );
  }
}

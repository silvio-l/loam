/// The kind of problem the suppression audit found with a `// loam-ignore:`
/// directive.
enum SuppressionNoticeKind {
  /// The directive is valid and active but suppressed no finding.
  unused('unused'),

  /// The directive's `until=` date has passed; it no longer suppresses.
  expired('expired'),

  /// The directive names a rule but gives no reason (Grund-Pflicht).
  missingReason('missing-reason'),

  /// The directive names no rule ID at all.
  missingRule('missing-rule'),

  /// The `until=` date is not a valid `YYYY-MM-DD` calendar date.
  invalidExpiry('invalid-expiry'),

  /// The directive names a rule ID that does not exist.
  unknownRule('unknown-rule'),

  /// `until=` appears inside the reason text instead of directly after the rule
  /// ID, so it is plain text and the directive never expires.
  misplacedExpiry('misplaced-expiry');

  const SuppressionNoticeKind(this.id);

  /// Stable, machine-readable token (used in JSON/SARIF output).
  final String id;
}

/// One audit remark about a single `// loam-ignore:` directive.
///
/// Notices are **warnings, not findings**: they never enter the findings list,
/// the baseline or the gate decision (product decision: warn, do not abort —
/// see issue #5).
class SuppressionNotice {
  /// Creates a [SuppressionNotice].
  const SuppressionNotice({
    required this.kind,
    required this.filePath,
    required this.line,
    required this.message,
    this.ruleId,
  });

  /// What is wrong with the directive.
  final SuppressionNoticeKind kind;

  /// Project-relative POSIX path of the file holding the directive.
  final String filePath;

  /// 1-based line of the directive comment.
  final int line;

  /// The rule ID the directive names, or `null` when it names none.
  final String? ruleId;

  /// Human-readable explanation including the next action.
  final String message;

  /// One-line plain-text form: `path:line  kind  message`.
  String toLine() => '$filePath:$line  ${kind.id}  $message';
}

/// The result of the suppression audit for one run: how many findings each rule
/// had suppressed, plus the [notices] about questionable directives.
class SuppressionAudit {
  /// Creates a [SuppressionAudit].
  const SuppressionAudit({
    this.byRule = const {},
    this.notices = const [],
    this.evaluatedOn,
  });

  /// An audit with nothing to report.
  const SuppressionAudit.empty()
    : byRule = const {},
      notices = const [],
      evaluatedOn = null;

  /// The calendar day (`YYYY-MM-DD`) against which `until=` dates were judged,
  /// or `null` when no directive carries an expiry date. Expiry makes the
  /// result depend on the clock; this names the day so a report stays
  /// reproducible from its own content.
  final String? evaluatedOn;

  /// Findings removed by suppression (inline directives and globs), per rule ID.
  final Map<String, int> byRule;

  /// Problems with directives, sorted by path, line, kind.
  final List<SuppressionNotice> notices;

  /// `true` when there is nothing to show.
  bool get isEmpty => byRule.isEmpty && notices.isEmpty;

  /// Plain-text lines for terminal-style reporters; empty when [isEmpty].
  ///
  /// Rules are listed alphabetically, so the output is deterministic.
  List<String> toSummaryLines() {
    final lines = <String>[];
    if (byRule.isNotEmpty) {
      final ids = byRule.keys.toList()..sort();
      lines.add(
        'suppressed by rule: ${ids.map((id) => '$id ${byRule[id]}').join(', ')}',
      );
    }
    for (final n in notices) {
      lines.add('warning: ${n.toLine()}');
    }
    return lines;
  }

  /// Structured form for JSON/SARIF output.
  Map<String, dynamic> toJson() {
    final ids = byRule.keys.toList()..sort();
    return {
      if (evaluatedOn != null) 'evaluatedOn': evaluatedOn,
      'byRule': {for (final id in ids) id: byRule[id]},
      'notices': [
        for (final n in notices)
          {
            'kind': n.kind.id,
            'filePath': n.filePath,
            'line': n.line,
            'ruleId': n.ruleId,
            'message': n.message,
          },
      ],
    };
  }
}

import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

import '../config/loam_config.dart';
import '../model/finding.dart';
import 'inline_suppression_scanner.dart';
import 'suppression_audit.dart';

/// The outcome of [SuppressionEngine.apply]: surviving [findings] plus the
/// [audit] of what was suppressed and which directives look wrong.
class SuppressionResult {
  /// Creates a [SuppressionResult].
  const SuppressionResult(this.findings, this.audit);

  /// Findings that survived suppression, in input order.
  final List<Finding> findings;

  /// Per-rule suppression counts and directive notices.
  final SuppressionAudit audit;
}

/// Filters [Finding]s based on active suppression sources.
///
/// **Deep Module contract:** callers interact only via [filter] — the internal
/// list of suppression sources is an implementation detail.
///
/// Current suppression sources (applied in order, union):
///   1. **Glob-source:** findings in files matched by [LoamConfig.ignoreGlobs]
///      are removed.
///   2. **Inline-directive source (issue 03):** findings annotated with
///      `// loam-ignore: <ruleId> – <reason>` are removed. Only the exact
///      (filePath, line, ruleId) triple is suppressed; other findings of the
///      same rule at different locations are not affected.
///
/// Glob patterns are matched against **project-relative** paths so that results
/// are machine-independent (Invariant 5 / reproducibility).
///
/// Suppression filters findings only — it does NOT affect [rulesetVersion].
/// The active rule set is unchanged; suppressed findings simply do not appear
/// in the output, the baseline, or the gate evaluation.
abstract final class SuppressionEngine {
  /// Returns a filtered copy of [findings], removing any finding that matches
  /// an active suppression source.
  ///
  /// **Source 1 — Glob:** any finding whose file matches a pattern in
  /// [config.ignoreGlobs] is removed.
  ///
  /// **Source 2 — Inline directives:** any finding whose `(filePath, line,
  /// ruleId)` is covered by a [LoamIgnoreDirective] in [inlineDirectives] is
  /// removed. A directive covers a finding when the directive's [ruleId]
  /// matches and the directive's line equals the finding's line (same line) or
  /// the finding's line equals directive.line + 1 (preceding-line form).
  ///
  /// [projectRoot] must be the absolute, normalised path of the project being
  /// analysed. It is used to derive project-relative paths for glob matching.
  ///
  /// Findings not matched by any suppression source are returned unchanged and
  /// in the same relative order as the input (deterministic, Invariant 5).
  static List<Finding> filter(
    List<Finding> findings,
    LoamConfig config,
    String projectRoot, {
    Set<LoamIgnoreDirective> inlineDirectives = const {},
    DateTime? today,
  }) => apply(
    findings,
    config,
    projectRoot,
    inlineDirectives: inlineDirectives,
    today: today,
  ).findings;

  /// Like [filter], but also audits the directives.
  ///
  /// - A directive whose `until=` date has passed on [today] (default: the
  ///   current date) no longer suppresses and yields an `expired` notice.
  /// - A live directive that suppressed no raw finding yields an `unused`
  ///   notice — but only when its rule ran ([auditedRuleIds]; `null` = all),
  ///   so `loam a11y` does not flag directives of rules it never executed.
  /// - A directive naming a rule outside [knownRuleIds] (`null` = skip the
  ///   check) yields an `unknown-rule` notice.
  /// - [scanIssues] (malformed directives from the scanner) are passed
  ///   through into the audit.
  /// - [SuppressionAudit.byRule] counts suppressed findings per rule (inline
  ///   directives and globs combined).
  ///
  /// - [SuppressionAudit.evaluatedOn] names the day `until=` dates were judged
  ///   against, set only when at least one directive has an expiry.
  ///
  /// Notices are warnings only; they never change [SuppressionResult.findings].
  static SuppressionResult apply(
    List<Finding> findings,
    LoamConfig config,
    String projectRoot, {
    Set<LoamIgnoreDirective> inlineDirectives = const {},
    List<SuppressionNotice> scanIssues = const [],
    Set<String>? auditedRuleIds,
    Set<String>? knownRuleIds,
    DateTime? today,
  }) {
    final now = today ?? DateTime.now();
    // Compile globs once per call (they are pure value objects).
    final globs = config.ignoreGlobs.map((pattern) => Glob(pattern)).toList();

    final notices = <SuppressionNotice>[...scanIssues];

    // Expired directives stop suppressing; unknown ones can never match.
    final live = <LoamIgnoreDirective>[];
    for (final d in inlineDirectives) {
      if (d.isExpiredOn(now)) {
        notices.add(
          SuppressionNotice(
            kind: SuppressionNoticeKind.expired,
            filePath: d.filePath,
            line: d.line,
            ruleId: d.ruleId,
            message:
                'loam-ignore for `${d.ruleId}` expired on '
                '${_isoDate(d.expires!)} and no longer suppresses; fix the '
                'finding or renew the date.',
          ),
        );
      } else if (knownRuleIds != null && !knownRuleIds.contains(d.ruleId)) {
        notices.add(
          SuppressionNotice(
            kind: SuppressionNoticeKind.unknownRule,
            filePath: d.filePath,
            line: d.line,
            ruleId: d.ruleId,
            message:
                'loam-ignore names unknown rule `${d.ruleId}`; fix the rule '
                'ID or remove the directive.',
          ),
        );
      } else {
        live.add(d);
      }
    }

    final used = <LoamIgnoreDirective>{};
    final byRule = <String, int>{};
    final kept = <Finding>[];
    for (final finding in findings) {
      var suppressed = false;
      if (globs.isNotEmpty) {
        final relPath = _relativise(finding.filePath, projectRoot);
        if (_isGlobSuppressed(relPath, globs)) suppressed = true;
      }
      // Every covering directive counts as used, even if a glob already hides
      // the finding — the directive is not dead weight in that case.
      for (final d in _coveringDirectives(finding, live)) {
        used.add(d);
        suppressed = true;
      }
      if (suppressed) {
        byRule[finding.ruleId] = (byRule[finding.ruleId] ?? 0) + 1;
      } else {
        kept.add(finding);
      }
    }

    for (final d in live) {
      if (used.contains(d)) continue;
      if (auditedRuleIds != null && !auditedRuleIds.contains(d.ruleId)) {
        continue;
      }
      notices.add(
        SuppressionNotice(
          kind: SuppressionNoticeKind.unused,
          filePath: d.filePath,
          line: d.line,
          ruleId: d.ruleId,
          message:
              'loam-ignore for `${d.ruleId}` suppresses nothing; remove the '
              'directive.',
        ),
      );
    }

    notices.sort((a, b) {
      final c = a.filePath.compareTo(b.filePath);
      if (c != 0) return c;
      final l = a.line.compareTo(b.line);
      if (l != 0) return l;
      return a.kind.index.compareTo(b.kind.index);
    });

    return SuppressionResult(
      // Fast path preserved: nothing removed → same list instance.
      kept.length == findings.length ? findings : kept,
      SuppressionAudit(
        byRule: byRule,
        notices: notices,
        // Only when an expiry date was judged; otherwise the report does not
        // depend on the clock and carries no date.
        evaluatedOn: inlineDirectives.any((d) => d.expires != null)
            ? _isoDate(now)
            : null,
      ),
    );
  }

  static String _isoDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Returns `true` when [relPath] matches any of [globs].
  static bool _isGlobSuppressed(String relPath, List<Glob> globs) {
    for (final glob in globs) {
      if (glob.matches(relPath)) return true;
    }
    return false;
  }

  /// Returns every directive in [directives] that covers [finding].
  ///
  /// Matching rule (applied per directive):
  /// - `directive.filePath == finding.filePath`
  /// - `directive.ruleId == finding.ruleId`
  /// - `directive.line == finding.line` (same-line form)
  ///   OR `finding.line == directive.line + 1` (preceding-line form)
  ///
  /// Only the exactly addressed (filePath, line, ruleId) combination is
  /// suppressed. Other findings of the same rule at different lines/files are
  /// NOT affected.
  static Iterable<LoamIgnoreDirective> _coveringDirectives(
    Finding finding,
    Iterable<LoamIgnoreDirective> directives,
  ) sync* {
    // Directives carry POSIX paths; a finding path built with the host's
    // separators (Windows) must still match its directive.
    final findingPath = finding.filePath.replaceAll(r'\', '/');
    for (final directive in directives) {
      if (directive.ruleId != finding.ruleId) continue;
      if (directive.filePath != findingPath) continue;
      if (directive.line == finding.line ||
          finding.line == directive.line + 1) {
        yield directive;
      }
    }
  }

  /// Derives a project-relative POSIX path from [absolutePath].
  ///
  /// Uses forward slashes so that patterns like `test/fixtures/**` work
  /// identically on all platforms (Invariant 5).
  static String _relativise(String path, String projectRoot) {
    // Findings carry a project-relative [Finding.filePath] (see the Finding
    // doc and every rule). Only relativise when the path is absolute — calling
    // p.relative() on an already-relative path would resolve it against the
    // process CWD, silently breaking glob suppression whenever loam runs from a
    // different directory than the analysed root (e.g. `loam gate
    // --project-root sub` from the repo root, or in CI). Mirrors the reporter's
    // `p.isAbsolute(rawPath) ? p.relative(...) : rawPath` logic.
    final rel = p.isAbsolute(path) ? p.relative(path, from: projectRoot) : path;
    // Convert to forward-slash form for cross-platform glob matching.
    return p.posix.joinAll(p.split(rel));
  }
}

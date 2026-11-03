import 'package:analyzer/dart/ast/token.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import 'suppression_audit.dart';

/// A single parsed `// loam-ignore: <ruleId> – <reason>` directive.
///
/// Carries the project-relative POSIX [filePath], the 1-based [line] the
/// comment appears on, and the [ruleId] extracted from the directive.
///
/// [filePath] is a **POSIX project-relative path** (the same format used by
/// [Finding.filePath]) so that directive-to-finding comparison is a simple
/// string equality check (Invariant 5 — reproducibility / machine independence).
///
/// **Validity:** a directive is only parsed into a [LoamIgnoreDirective] when
/// it contains both a non-empty [ruleId] AND a non-empty reason text after the
/// rule ID (Grund-Pflicht). Directives that lack either are silently ignored.
class LoamIgnoreDirective {
  /// Creates a [LoamIgnoreDirective].
  const LoamIgnoreDirective({
    required this.filePath,
    required this.line,
    required this.ruleId,
    this.expires,
  });

  /// Project-relative POSIX path of the file that contains the directive.
  ///
  /// Matches the format of [Finding.filePath] produced by the rule layer so
  /// that directive-to-finding comparison is a plain `==` check.
  final String filePath;

  /// 1-based line number of the `// loam-ignore:` comment.
  final int line;

  /// The rule ID extracted from the directive (e.g. `unused-public-exports`).
  final String ruleId;

  /// Last day (inclusive, calendar date, stored as UTC midnight) the directive
  /// is active, from an optional `until=YYYY-MM-DD` token; `null` = never
  /// expires.
  final DateTime? expires;

  /// Whether the directive has expired on the calendar day of [today].
  ///
  /// Only the year/month/day fields of [today] are used, **as given**: the
  /// runner's clock returns `DateTime.now()` (local time), so the machine's
  /// local calendar day decides; an injected UTC clock decides by its UTC day.
  bool isExpiredOn(DateTime today) {
    final e = expires;
    if (e == null) return false;
    return DateTime.utc(today.year, today.month, today.day).isAfter(e);
  }

  @override
  String toString() => 'LoamIgnoreDirective($filePath:$line, $ruleId)';
}

/// Everything [InlineSuppressionScanner.scanWithIssues] found: the usable
/// [directives] plus [issues] for malformed ones (missing rule/reason,
/// invalid expiry date).
class ScannedDirectives {
  /// Creates a [ScannedDirectives].
  const ScannedDirectives(this.directives, this.issues);

  /// Valid directives (rule ID + reason present, expiry parsable).
  final Set<LoamIgnoreDirective> directives;

  /// Notices for directives that were rejected.
  final List<SuppressionNotice> issues;
}

/// Scans resolved Dart compilation units for `// loam-ignore: <ruleId> – <reason>`
/// directives using the **analyzer's token/comment model** — NOT by running a
/// regex over the raw file content (Invariant 1: Semantics before syntax).
///
/// ## Distinction from automatic codegen-input suppression
///
/// [InlineSuppressionScanner] handles *user-authored* suppression directives
/// placed intentionally in source code. This is categorically different from
/// the *automatic* suppression performed by `CodegenInputClassifier`, which
/// identifies code-gen input classes via the element model and suppresses their
/// findings without any source-level annotation. The two mechanisms are
/// independent and complementary; neither replaces the other.
///
/// ## Format
///
/// ```dart
/// // loam-ignore: unused-public-exports – This export is used by the plugin
/// class MyClass {}          // ← directive on the preceding line
///
/// class OtherClass {}  // loam-ignore: unused-public-exports – Reason here
/// ```
///
/// The pattern is: `// loam-ignore: <ruleId>` followed by whitespace and then
/// a separator (` – `, ` - `, or just ` `) and then the reason text.
/// Concretely:
/// - Everything after `// loam-ignore:` and up to the first whitespace is the
///   rule ID.
/// - An optional `until=YYYY-MM-DD` token directly after the rule ID makes the
///   directive expire after that day (`// loam-ignore: rule until=2026-12-31 – why`).
/// - The rest (trimmed) is the reason. If the reason is empty, the directive
///   is invalid (Grund-Pflicht) and reported by the suppression audit.
///
/// ## Matching rules
///
/// A [LoamIgnoreDirective] suppresses a finding when:
/// 1. The finding's `filePath` equals the directive's `filePath`.
/// 2. The finding's `ruleId` equals the directive's `ruleId`.
/// 3. The finding's `line` equals the directive's `line` (same line) OR
///    the finding's `line` equals `directive.line + 1` (finding on the line
///    immediately following the comment).
///
/// Only the exactly matching finding is suppressed; other findings of the same
/// rule at different locations are not affected.
abstract final class InlineSuppressionScanner {
  /// The directive prefix used to identify loam-ignore comments.
  static const String _prefix = '// loam-ignore:';

  /// Scans all resolved compilation units in [loadResult] and returns the set
  /// of valid [LoamIgnoreDirective]s found.
  ///
  /// [projectRoot] is the absolute, normalised path of the project root. It is
  /// used to convert absolute file paths from the [ProjectLoader] into the
  /// project-relative POSIX paths stored in [LoamIgnoreDirective.filePath],
  /// matching the format used by [Finding.filePath] (Invariant 5).
  ///
  /// Invalid directives (missing rule ID or missing reason text) are silently
  /// dropped. This method never throws.
  static Set<LoamIgnoreDirective> scan(
    ProjectLoadResult loadResult,
    String projectRoot,
  ) => scanWithIssues(loadResult, projectRoot).directives;

  /// Like [scan], but also returns a [SuppressionNotice] for every directive
  /// that was rejected (no rule ID, no reason, invalid `until=` date) instead
  /// of dropping it silently.
  static ScannedDirectives scanWithIssues(
    ProjectLoadResult loadResult,
    String projectRoot,
  ) {
    final directives = <LoamIgnoreDirective>{};
    final issues = <SuppressionNotice>[];
    final root = p.normalize(p.absolute(projectRoot));

    for (final file in loadResult.resolved) {
      final unit = file.parsed.unit;
      final lineInfo = file.parsed.lineInfo;
      // Convert to the project-relative POSIX path that Finding.filePath uses.
      final filePath = _toRelativePosix(file.path, root);

      // Walk the token stream via beginToken → next.
      // Comments are not tokens themselves — they are attached to the NEXT
      // token as a linked list of CommentTokens in `precedingComments`.
      var token = unit.beginToken;
      while (true) {
        var comment = token.precedingComments;
        while (comment != null) {
          final lexeme = comment.lexeme;
          if (lexeme.startsWith(_prefix)) {
            final location = lineInfo.getLocation(comment.offset);
            final parsed = _parseDirective(
              lexeme: lexeme,
              filePath: filePath,
              line: location.lineNumber,
            );
            if (parsed.directive != null) directives.add(parsed.directive!);
            if (parsed.issue != null) issues.add(parsed.issue!);
          }
          // CommentToken.next is typed as Token? in the abstract API,
          // but for a CommentToken the next in a comment chain is always
          // another CommentToken (or null). Cast to CommentToken? safely.
          final nextComment = comment.next;
          if (nextComment is CommentToken) {
            comment = nextComment;
          } else {
            comment = null;
          }
        }

        if (token.isEof) break;
        // token.next is typed as Token? — in practice it is always non-null
        // before EOF (the stream ends with an EOF sentinel whose next points to
        // itself), so this is safe.
        token = token.next!;
      }
    }

    return ScannedDirectives(directives, issues);
  }

  /// Parses a single `// loam-ignore: …` comment [lexeme].
  ///
  /// Returns the directive when valid, otherwise a [SuppressionNotice] saying
  /// why it was rejected: no rule ID, no reason (Grund-Pflicht), or an invalid
  /// `until=` date.
  static ({LoamIgnoreDirective? directive, SuppressionNotice? issue})
  _parseDirective({
    required String lexeme,
    required String filePath,
    required int line,
  }) {
    SuppressionNotice issue(
      SuppressionNoticeKind kind,
      String message, [
      String? ruleId,
    ]) => SuppressionNotice(
      kind: kind,
      filePath: filePath,
      line: line,
      ruleId: ruleId,
      message: message,
    );

    // Strip the prefix and trim leading/trailing whitespace.
    var rest = lexeme.substring(_prefix.length).trim();

    if (rest.isEmpty) {
      return (
        directive: null,
        issue: issue(
          SuppressionNoticeKind.missingRule,
          'loam-ignore names no rule ID; write `// loam-ignore: <ruleId> – <reason>`.',
        ),
      );
    }

    // The rule ID is the first whitespace-delimited token.
    final ruleMatch = RegExp(r'^(\S+)\s*').firstMatch(rest)!;
    final ruleId = ruleMatch.group(1)!;
    rest = rest.substring(ruleMatch.end);

    // Optional expiry token directly after the rule ID.
    DateTime? expires;
    final untilMatch = RegExp(r'^until=(\S*)\s*').firstMatch(rest);
    if (untilMatch != null) {
      expires = _parseDate(untilMatch.group(1)!);
      if (expires == null) {
        return (
          directive: null,
          issue: issue(
            SuppressionNoticeKind.invalidExpiry,
            'loam-ignore for `$ruleId` has an invalid expiry '
            '`until=${untilMatch.group(1)}`; use a real date as '
            '`until=YYYY-MM-DD`. The directive is ignored.',
            ruleId,
          ),
        );
      }
      rest = rest.substring(untilMatch.end);
    }

    // Reason: strip common separators (–, -, :) and whitespace.
    final reason = rest.replaceAll(RegExp(r'^[\s\-–:]+'), '').trim();
    if (reason.isEmpty) {
      return (
        directive: null,
        issue: issue(
          SuppressionNoticeKind.missingReason,
          'loam-ignore for `$ruleId` has no reason and suppresses nothing; '
          'add one after the rule ID or remove the directive.',
          ruleId,
        ),
      );
    }

    // `until=` later in the text is plain reason: the directive stays valid but
    // never expires — say so instead of ignoring it silently.
    final misplaced = expires == null && RegExp(r'\buntil=').hasMatch(reason);
    return (
      directive: LoamIgnoreDirective(
        filePath: filePath,
        line: line,
        ruleId: ruleId,
        expires: expires,
      ),
      issue: misplaced
          ? issue(
              SuppressionNoticeKind.misplacedExpiry,
              'loam-ignore for `$ruleId` has `until=` inside the reason, so it '
              'never expires; move it directly after the rule ID '
              '(`// loam-ignore: $ruleId until=YYYY-MM-DD – <reason>`).',
              ruleId,
            )
          : null,
    );
  }

  /// Parses a strict `YYYY-MM-DD` calendar date to UTC midnight, or `null`.
  static DateTime? _parseDate(String text) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(text);
    if (m == null) return null;
    final y = int.parse(m.group(1)!);
    final mo = int.parse(m.group(2)!);
    final d = int.parse(m.group(3)!);
    final date = DateTime.utc(y, mo, d);
    // Reject overflow such as 2026-02-31 (DateTime normalises to March).
    if (date.year != y || date.month != mo || date.day != d) return null;
    return date;
  }

  /// Converts [absolutePath] to a project-relative POSIX path.
  ///
  /// Uses forward slashes so the result matches [Finding.filePath] on all
  /// platforms (Invariant 5 — cross-platform reproducibility).
  static String _toRelativePosix(String absolutePath, String projectRoot) {
    final rel = p.relative(absolutePath, from: projectRoot);
    return p.posix.joinAll(p.split(rel));
  }
}

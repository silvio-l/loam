import 'package:analyzer/dart/ast/token.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';

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
  const LoamIgnoreDirective({
    required this.filePath,
    required this.line,
    required this.ruleId,
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

  @override
  String toString() => 'LoamIgnoreDirective($filePath:$line, $ruleId)';
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
/// - The rest (trimmed) is the reason. If the reason is empty, the directive
///   is invalid (Grund-Pflicht).
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
  ) {
    final directives = <LoamIgnoreDirective>{};
    final root = p.normalize(p.absolute(projectRoot));

    for (final file in loadResult.resolved) {
      final unit = file.result.unit;
      final lineInfo = file.result.lineInfo;
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
            final directive = _parseDirective(
              lexeme: lexeme,
              filePath: filePath,
              line: location.lineNumber,
            );
            if (directive != null) {
              directives.add(directive);
            }
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

    return directives;
  }

  /// Parses a single `// loam-ignore: …` comment [lexeme] into a
  /// [LoamIgnoreDirective], or returns `null` if the directive is invalid.
  ///
  /// Invalid cases (both silently dropped):
  /// - The part after `// loam-ignore:` contains no non-whitespace characters
  ///   → no rule ID.
  /// - The directive contains a rule ID but no reason text → Grund-Pflicht
  ///   violated.
  static LoamIgnoreDirective? _parseDirective({
    required String lexeme,
    required String filePath,
    required int line,
  }) {
    // Strip the prefix and trim leading/trailing whitespace.
    final rest = lexeme.substring(_prefix.length).trim();

    if (rest.isEmpty) return null; // no content at all

    // The rule ID is the first whitespace-delimited token.
    // Everything after it (trimmed) is the reason.
    final spaceIndex = rest.indexOf(' ');

    final String ruleId;
    final String reason;
    if (spaceIndex == -1) {
      // Only a rule ID, no reason — Grund-Pflicht violated.
      ruleId = rest;
      reason = '';
    } else {
      ruleId = rest.substring(0, spaceIndex);
      // Reason: strip common separators (–, -, :) and whitespace.
      reason = rest
          .substring(spaceIndex)
          .replaceAll(RegExp(r'^[\s\-–:]+'), '')
          .trim();
    }

    if (ruleId.isEmpty) return null;
    if (reason.isEmpty) return null; // Grund-Pflicht: reason is mandatory

    return LoamIgnoreDirective(filePath: filePath, line: line, ruleId: ruleId);
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

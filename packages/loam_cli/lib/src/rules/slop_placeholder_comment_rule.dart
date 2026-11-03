import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import '../model/project_path.dart';
import 'generated_file.dart';
import 'rule.dart';

/// Detects placeholder comments that stand in for code an AI agent left out:
/// `// ... rest of code`, `// ... existing code ...`, `// rest of the
/// implementation here`, `// your code here`.
///
/// Rule ID: `slop-placeholder-comment`
///
/// Such a comment is the visible trace of a truncated edit: the agent wrote a
/// marker instead of the code it was supposed to keep or write, so the file
/// compiles but a part of the behaviour is silently missing.
///
/// A `//` or `/* */` comment is reported only when its **whole text** is one
/// of the closed placeholder phrases (see [_placeholderPatterns]); a longer
/// sentence that merely mentions "the rest of the code" is never reported.
/// The phrases are:
///
/// - an ellipsis followed by an elision phrase, optionally closed by another
///   ellipsis or wrapped in brackets: `// ... rest of code`,
///   `// ...existing code...`, `// ... other methods`.
/// - the same elision phrase without ellipsis only when it ends in a fixed
///   marker word: `// rest of the implementation here`,
///   `// existing code remains unchanged`, or is the bare `rest of the code`.
/// - a "fill in here" placeholder: `// your code here`, `// add
///   implementation here`, `// implementation goes here`.
///
/// What this rule deliberately does **NOT** catch:
/// - `///` Dart-doc comments (real documentation is never flagged).
/// - A bare `// ...` without any words, and any prose comment that is longer
///   than the phrase.
/// - Generated files (`*.g.dart`, `*.freezed.dart`, etc.).
///
/// **Semantic anchor (fingerprint stability):**
/// `placeholder-comment:<normalised text>:n` — `n` counts earlier identical
/// placeholder comments in the same file, so neither line shifts nor other
/// edits change the anchor (same scheme as the context-free categories of
/// `slop-narrative-comment`).
///
/// **Finding contract:** `severity`: [Severity.warning], `kind`:
/// `'placeholder-comment'`, `remedy`: imperative fix instruction.
///
/// **Suppression:**
/// `// loam-ignore: slop-placeholder-comment – <reason>` on or before the
/// comment's line.
class SlopPlaceholderCommentRule implements FileRule {
  /// The stable rule ID for [SlopPlaceholderCommentRule].
  static const String ruleIdStatic = 'slop-placeholder-comment';

  /// Creates a [SlopPlaceholderCommentRule] rooted at [projectRoot].
  const SlopPlaceholderCommentRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  final String projectRoot;

  @override
  String get ruleId => ruleIdStatic;

  @override
  RuleCategory get category => RuleCategory.slop;

  @override
  List<Finding> run(ProjectLoadResult result) => runPerFile(this, result);

  @override
  List<Finding> runFile(LoadedFile file) {
    if (isGeneratedDartFile(file.path)) return const [];
    final findings = <Finding>[];
    _scanFile(
      file.parsed.unit,
      projectRelativePosixPath(file.path, projectRoot),
      findings,
    );
    return findings;
  }

  void _scanFile(
    CompilationUnit unit,
    String relativePath,
    List<Finding> findings,
  ) {
    final occurrences = <String, int>{};
    Token token = unit.beginToken;
    while (true) {
      Token? comment = token.precedingComments;
      while (comment != null) {
        final normalized = _placeholderText(comment);
        if (normalized != null) {
          final idx = occurrences[normalized] ?? 0;
          occurrences[normalized] = idx + 1;
          final location = unit.lineInfo.getLocation(comment.offset);
          findings.add(
            Finding(
              ruleId: ruleId,
              severity: Severity.warning,
              filePath: relativePath,
              line: location.lineNumber,
              column: location.columnNumber,
              message:
                  'Placeholder comment `${_lfLineBreaks(comment.lexeme.trim())}` stands in '
                  'for code that is not here — part of the behaviour is '
                  'missing.',
              fingerprint: computeFingerprint(
                ruleId: ruleId,
                relativePath: relativePath,
                semanticAnchor: 'placeholder-comment:$normalized:$idx',
              ),
              kind: 'placeholder-comment',
              remedy:
                  'Write out the code the comment stands for, or delete the '
                  'comment if nothing was meant to be here. Do not leave a '
                  'marker in place of an implementation.',
            ),
          );
        }
        comment = comment.next;
      }
      if (token.type == TokenType.EOF) break;
      token = token.next!;
    }
  }
}

/// [text] with CRLF and lone CR line breaks written as LF, so a block
/// comment quoted in the message reads the same in a CRLF checkout.
String _lfLineBreaks(String text) => text.replaceAll(RegExp(r'\r\n?'), '\n');

/// Elision subject: "rest of (the) code", "existing code", "other methods".
const String _subject =
    r'(?:the\s+)?(?:'
    r'rest\s+of\s+(?:the\s+|your\s+|this\s+)?(?:\w+\s+)?'
    r'(?:code|implementation|class|method|methods|function|functions|logic|body|content|setup|widget)'
    r'|(?:existing|remaining|previous|unchanged|original|other|same)\s+(?:\w+\s+)?'
    r'(?:code|implementation|methods?|functions?|fields?|members?|logic|content|class|classes|imports?|widgets?|properties|setup|body|cases?)'
    r')';

/// Marker words that may follow a subject and confirm it is a placeholder.
const String _marker =
    r'(?:here|remains?|stays?|continues|follows|omitted|unchanged|as\s+before|'
    r'as\s+is|goes\s+here|is\s+unchanged|(?:remains?|stays?)\s+(?:the\s+)?(?:same|unchanged))';

const String _ellipsis = r'(?:\.\.\.|…)';

final List<RegExp> _placeholderPatterns = [
  // `... rest of code`, `...existing code ...`, `(... other methods)`.
  RegExp(
    '^[\\(\\[]?$_ellipsis\\s*$_subject(?:\\s+$_marker)*\\s*$_ellipsis?[\\)\\]]?\$',
  ),
  // No ellipsis: only with a confirming marker word.
  RegExp('^[\\(\\[]?$_subject(?:\\s+$_marker)+[\\)\\]]?\$'),
  // The bare classic.
  RegExp(r'^rest\s+of\s+(?:the\s+)?(?:code|implementation)$'),
  // Fill-in placeholders.
  RegExp(
    r'^(?:(?:add|insert|put|write)\s+(?:your\s+|the\s+|more\s+)?(?:own\s+)?)?'
    r'(?:(?:your\s+)?(?:code|implementation|logic)\s+(?:goes\s+)?here)$',
  ),
];

/// The normalised text of [comment] when it is a placeholder comment, else
/// `null`. Doc comments (`///`, `/**`) are never placeholders.
String? _placeholderText(Token comment) {
  final lexeme = comment.lexeme;
  String text;
  if (comment.type == TokenType.SINGLE_LINE_COMMENT) {
    if (lexeme.startsWith('///')) return null;
    text = lexeme.substring(2);
  } else if (comment.type == TokenType.MULTI_LINE_COMMENT) {
    if (lexeme.startsWith('/**')) return null;
    text = lexeme.substring(2, lexeme.length - 2);
  } else {
    return null;
  }
  text = text
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim()
      .toLowerCase()
      .replaceFirst(RegExp(r'[.;]+$'), '');
  if (text.isEmpty) return null;
  return _placeholderPatterns.any((p) => p.hasMatch(text)) ? text : null;
}

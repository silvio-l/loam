import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'generated_file.dart';
import 'rule.dart';

/// Detects `//` comments that add no information beyond what the code
/// already shows — either because they restate a declaration's name, or
/// because their content is structurally content-free (decoration, a bare
/// category label, emoji-only, a redundant end-of-block marker, or a TODO
/// with no concrete, actionable scope).
///
/// Rule ID: `slop-narrative-comment`
///
/// Findings come from two independent checks over the same file:
///
/// **A. Declaration-adjacent narrative comments** — a single-line `//`
/// comment that appears on the line directly before a class, method,
/// getter/setter, constructor, or top-level function declaration (no blank
/// lines between) and whose normalized text satisfies at least one of:
///
/// 1. **Name-equal** — after stripping `//`, trimming whitespace, and
///    lowercasing, the comment text equals the lowercased declaration name.
/// 2. **Fixed restatement** — the normalized text is in the small, fixed list:
///    `constructor`, `getter`, `setter`, `build method`.
/// 3. **"the NAME method/widget" pattern** — the normalized text equals
///    `the {name} method` or `the {name} widget` where `{name}` is the
///    lowercased declaration name.
///
/// **B. Context-free structural slop comments** — every single-line `//`
/// comment in the file (regardless of what follows it — a declaration, a
/// statement, or nothing) is independently classified into one of:
///
/// 4. **Banner / divider** (`kind: 'banner-comment'`) — a decorative
///    separator made only of repeated punctuation (`// ====`, `// ****`) or a
///    punctuation-framed label (`// ****** SECTION ******`). Plain hyphen
///    dividers (`// ---------------`) are deliberately excluded — see
///    [_pureDividerPattern].
/// 5. **Empty category label** (`kind: 'empty-category-label'`) — the
///    normalized text is a generic structural label with no information of
///    its own, e.g. `main logic`, `helper function`, `core logic`, `error
///    handling`, `initialization` (fixed list, see [_categoryLabels]).
/// 6. **Emoji-only decoration** (`kind: 'emoji-decoration'`) — the comment,
///    once every emoji code point and light punctuation is stripped, has no
///    remaining text (e.g. `// 🚀`, `// ✅ ✅`).
/// 7. **End-of-block marker** (`kind: 'end-marker-comment'`) — a short
///    redundant marker such as `// end if`, `// End processOrder`, `// end
///    for loop`; indentation and the closing brace already show the block
///    boundary.
/// 8. **Vague TODO** (`kind: 'vague-todo'`) — a `TODO`/`FIXME` comment whose
///    body (after the prefix) is a bare generic directive with no concrete
///    object, condition, or reference (fixed list, see [_vagueTodoPhrases]).
///    A TODO with real substance (e.g. `TODO: handle null case when userId
///    is missing (see #123)`) is a **legitimate** TODO and is never flagged.
///
/// What this rule deliberately does **NOT** catch:
/// - `///` Dart-doc comments — real documentation is never flagged (tabu).
/// - Block comments (`/* */`).
/// - Plain hyphen dividers (`// ---------------`) — a common, legitimate
///   section-separator convention, not an AI-slop signal; only `=`/`*`/`#`/
///   `~`/`_` decoration is treated as a banner.
/// - `//` comments whose text does not match any of the categories above —
///   informative `//` comments are never flagged (no fuzzy heuristic quality
///   scoring; that is the LLM layer, sprint-17).
/// - Generated files (`*.g.dart`, `*.freezed.dart`, etc.) — excluded via
///   [isGeneratedDartFile] at the start of each file loop.
///
/// **Semantic anchor (fingerprint stability):**
/// - Declaration-adjacent findings (category A): `qualifiedDeclarationName:
///   narrative-comment:occurrenceIndex` — `qualifiedDeclarationName` is the
///   qualified name (e.g. `MyClass.build`) and `occurrenceIndex` counts prior
///   occurrences of the same qualified name.
/// - Context-free findings (category B): `kind:normalizedCommentText:
///   occurrenceIndex` — `occurrenceIndex` counts prior occurrences of the
///   same `(kind, normalizedCommentText)` pair in the file. Anchoring on the
///   normalized text itself (rather than a file offset) keeps the fingerprint
///   stable when unrelated code shifts around the comment (Invariant 5).
///
/// **Finding contract:**
/// - `severity`: [Severity.info]
/// - `kind`: `'narrative-comment'` for category A; one of
///   `'banner-comment'`, `'empty-category-label'`, `'emoji-decoration'`,
///   `'end-marker-comment'`, `'vague-todo'` for category B.
/// - `remedy`: imperative fix instruction
/// - `wcagRef`: null (slop rule — no WCAG reference)
///
/// **Suppression:**
/// `// loam-ignore: slop-narrative-comment – <reason>` on or before the line
/// of the offending comment suppresses the finding.
class SlopNarrativeCommentRule implements Rule {
  /// The stable rule ID for [SlopNarrativeCommentRule].
  ///
  /// Exposed as a static constant so callers can filter findings by rule ID
  /// without instantiating the rule or risking a typo.
  static const String ruleIdStatic = 'slop-narrative-comment';

  /// Creates a [SlopNarrativeCommentRule] rooted at [projectRoot].
  ///
  /// [projectRoot] is the absolute path of the analysed package.
  const SlopNarrativeCommentRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  final String projectRoot;

  @override
  String get ruleId => 'slop-narrative-comment';

  @override
  RuleCategory get category => RuleCategory.slop;

  // loam-ignore: code-duplicates – run() body is identical boilerplate across all Rule implementations; a shared mixin would couple unrelated rule files together.
  @override
  List<Finding> run(ProjectLoadResult result) {
    final findings = <Finding>[];

    for (final file in result.resolved) {
      // Skip generated files — *.g.dart, *.freezed.dart, *.mocks.dart, gen-l10n.
      if (isGeneratedDartFile(file.path)) continue;

      final relativePath = p.relative(file.path, from: projectRoot);

      final visitor = _NarrativeCommentVisitor(
        ruleId: ruleId,
        relativePath: relativePath,
        findings: findings,
      );
      file.result.unit.accept(visitor);
    }

    return findings;
  }
}

/// One preset (message, remedy) pair for a context-free comment category.
class _CommentSpec {
  const _CommentSpec({required this.message, required this.remedy});
  final String message;
  final String remedy;
}

/// Message/remedy text per context-free `kind`. Keyed by the same string
/// used as [Finding.kind] for that category.
const Map<String, _CommentSpec> _contextFreeSpecs = {
  'banner-comment': _CommentSpec(
    message:
        'Decorative divider/banner comment adds no information — code '
        'structure and formatting already delimit sections.',
    remedy:
        'Remove the banner comment. To communicate section structure, use '
        'clear class/method names instead of ASCII-art dividers.',
  ),
  'empty-category-label': _CommentSpec(
    message:
        'Comment only names a generic structural category — it adds no '
        'information beyond what the code already shows.',
    remedy:
        'Remove the label comment, or replace it with a specific note about '
        'behaviour, rationale, or an edge case the code does not make '
        'obvious on its own.',
  ),
  'emoji-decoration': _CommentSpec(
    message:
        'Comment consists solely of emoji decoration with no textual '
        'content.',
    remedy:
        'Remove the emoji-only comment — it carries no information for '
        'readers or tooling.',
  ),
  'end-marker-comment': _CommentSpec(
    message:
        'Redundant end-of-block marker — indentation and the closing brace '
        'already show where the block ends.',
    remedy: 'Remove the end-marker comment.',
  ),
  'vague-todo': _CommentSpec(
    message:
        'Vague TODO gives no concrete action, condition, or reference — it '
        "can't be acted on.",
    remedy:
        'Give the TODO a concrete scope (what to do, under what condition, '
        'or a reference such as an issue link), or remove it.',
  ),
};

/// Fixed list of generic structural category labels that carry no
/// information beyond naming a category every reader can already see from
/// the surrounding code (Abgrenzungsfall: no fuzzy scoring — a closed list).
const Set<String> _categoryLabels = {
  'main logic',
  'main function',
  'core logic',
  'business logic',
  'helper function',
  'helper functions',
  'utility function',
  'utility functions',
  'error handling',
  'initialization',
  'init',
  'setup',
  'cleanup',
};

/// Fixed list of generic TODO/FIXME bodies with no concrete object,
/// condition, or reference — matched against the normalized text *after*
/// the `TODO`/`FIXME` prefix (Abgrenzungsfall: a closed list, not fuzzy
/// scoring — mirrors [_categoryLabels]).
const Set<String> _vagueTodoPhrases = {
  '',
  'improve',
  'improve this',
  'improve later',
  'fix',
  'fix this',
  'fix it',
  'fix later',
  'fix it later',
  'clean up',
  'cleanup',
  'clean this up',
  'refactor',
  'refactor this',
  'refactor later',
  'optimize',
  'optimize this',
  'improve error handling',
  'handle this better',
  'handle errors better',
  'add validation',
  'add more validation',
  'update this',
  'review this',
  'check this',
  'finish this',
  'complete this',
  'implement this',
  'do this better',
  'make this better',
  'make better',
};

/// Matches a comment that is only decoration characters (`====`, `****`, …).
///
/// Deliberately excludes `-` — a plain hyphen divider/section-separator
/// (`// ---------------`) is a widespread, legitimate code-organisation
/// convention (this very codebase uses it throughout `lib/`), not an
/// AI-slop signal. Flagging it would make the rule fire on the maintainer's
/// own deliberate structure, not on decorative filler.
final RegExp _pureDividerPattern = RegExp(r'^[=*#~_]{3,}$');

/// Matches a comment framed by 2+ decoration characters on both ends, with
/// real content (and whitespace) in between, e.g. `****** SECTION ******`.
/// Excludes `-` for the same reason as [_pureDividerPattern].
final RegExp _framedLabelPattern = RegExp(r'^[=*#~_]{2,}.*[=*#~_]{2,}$');

/// Unicode ranges covering the common emoji blocks used for pure decoration.
final RegExp _emojiPattern = RegExp(
  r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{2B00}-\u{2BFF}\u{2190}-\u{21FF}\u{FE0F}]',
  unicode: true,
);

/// Matches `end <keyword…>` / bare `end` — a redundant block-end marker.
final RegExp _endMarkerPattern = RegExp(r'^end\s+\S');

/// Matches a `TODO`/`FIXME` comment, capturing the body after the prefix.
final RegExp _todoPattern = RegExp(
  r'^(?:TODO|FIXME)\s*:?\s*(.*)$',
  caseSensitive: false,
);

/// AST visitor that collects narrative `//` comments immediately before
/// class/member/function declarations, plus every context-free structural
/// slop comment (banner, empty-category-label, emoji-decoration,
/// end-marker-comment, vague-todo) anywhere in the file.
class _NarrativeCommentVisitor extends RecursiveAstVisitor<void> {
  _NarrativeCommentVisitor({
    required this.ruleId,
    required this.relativePath,
    required this.findings,
  });

  final String ruleId;
  final String relativePath;
  final List<Finding> findings;

  /// Occurrence counter keyed by qualified declaration name — category A.
  ///
  /// Ensures that multiple narrative comments for declarations with the same
  /// qualified name get distinct, deterministic fingerprints.
  final Map<String, int> _occurrenceCount = {};

  /// Occurrence counter keyed by `kind:normalizedCommentText` — category B.
  ///
  /// See the class doc comment on [SlopNarrativeCommentRule] for why the
  /// anchor is content-based rather than offset-based.
  final Map<String, int> _contextFreeOccurrence = {};

  @override
  void visitCompilationUnit(CompilationUnit node) {
    _scanContextFreeComments(node);
    super.visitCompilationUnit(node);
  }

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final className = node.namePart.typeName.lexeme;
    _check(node, className, className);
    super.visitClassDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final methodName = node.name.lexeme;
    // loam-ignore: code-duplicates – identical helper in each rule's private visitor; a shared mixin would couple unrelated rule files together.
    final className = _enclosingClassName(node);
    final qualified = '$className.$methodName';
    _check(node, methodName, qualified);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    // Only visit top-level functions (not local functions inside a body).
    if (node.parent is! CompilationUnit) return;
    final name = node.name.lexeme;
    _check(node, name, name);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final constructorName = node.name?.lexeme;
    // node.typeName is null when the new-style `new` / `factory` syntax is used.
    final className = node.typeName?.name ?? _enclosingClassName(node);
    final displayName = constructorName ?? className;
    final qualified = constructorName != null
        ? '$className.$constructorName'
        : className;
    _check(node, displayName, qualified);
    super.visitConstructorDeclaration(node);
  }

  // ---------------------------------------------------------------------------
  // Category A: declaration-adjacent check
  // ---------------------------------------------------------------------------

  void _check(AstNode node, String declarationName, String qualifiedName) {
    final commentToken = _immediatelyPrecedingLineComment(node);
    if (commentToken == null) return;

    final commentText = _normalizeCommentText(commentToken.lexeme);
    if (commentText.isEmpty) return;

    final normalizedName = declarationName.toLowerCase();
    if (!_isNarrativeComment(commentText, normalizedName)) return;

    final counterKey = qualifiedName;
    final idx = _occurrenceCount[counterKey] ?? 0;
    _occurrenceCount[counterKey] = idx + 1;

    final fingerprint = computeFingerprint(
      ruleId: ruleId,
      relativePath: relativePath,
      semanticAnchor: '$qualifiedName:narrative-comment:$idx',
    );

    final unit = node.root is CompilationUnit
        ? (node.root as CompilationUnit)
        : null;
    final lineInfo = unit?.lineInfo;
    final line = lineInfo?.getLocation(commentToken.offset).lineNumber ?? 1;
    final column = lineInfo?.getLocation(commentToken.offset).columnNumber;

    findings.add(
      Finding(
        ruleId: ruleId,
        severity: Severity.info,
        filePath: relativePath,
        line: line,
        column: column,
        message:
            '`//` comment restates the declaration name without adding '
            'information — remove it or replace it with a meaningful note.',
        fingerprint: fingerprint,
        kind: 'narrative-comment',
        remedy:
            'Remove the comment if it adds no information beyond the name. '
            'To document behaviour, contracts, or parameters, use a `///` '
            'Dart-doc comment instead of a `//` line comment.',
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Category B: context-free structural scan
  // ---------------------------------------------------------------------------

  /// Walks every token in [unit] (not just declaration begin-tokens) so that
  /// context-free categories are caught wherever they occur — before a
  /// statement, at the end of a block, or standing alone.
  void _scanContextFreeComments(CompilationUnit unit) {
    Token token = unit.beginToken;
    while (true) {
      Token? comment = token.precedingComments;
      while (comment != null) {
        if (comment.type == TokenType.SINGLE_LINE_COMMENT) {
          _checkContextFree(comment, unit);
        }
        comment = comment.next;
      }
      if (token.type == TokenType.EOF) break;
      token = token.next!;
    }
  }

  void _checkContextFree(Token commentToken, CompilationUnit unit) {
    final lexeme = commentToken.lexeme;
    if (lexeme.startsWith('///')) return; // Dartdoc-Tabu — never flagged.

    final category = _classifyContextFreeComment(lexeme);
    if (category == null) return;

    final normalized = _normalizeCommentText(lexeme);
    final counterKey = '$category:$normalized';
    final idx = _contextFreeOccurrence[counterKey] ?? 0;
    _contextFreeOccurrence[counterKey] = idx + 1;

    final fingerprint = computeFingerprint(
      ruleId: ruleId,
      relativePath: relativePath,
      semanticAnchor: '$counterKey:$idx',
    );

    final location = unit.lineInfo.getLocation(commentToken.offset);
    final spec = _contextFreeSpecs[category]!;

    findings.add(
      Finding(
        ruleId: ruleId,
        severity: Severity.info,
        filePath: relativePath,
        line: location.lineNumber,
        column: location.columnNumber,
        message: spec.message,
        fingerprint: fingerprint,
        kind: category,
        remedy: spec.remedy,
      ),
    );
  }

  /// Returns the context-free category (`kind`) [lexeme] belongs to, or
  /// `null` if it matches none of them.
  static String? _classifyContextFreeComment(String lexeme) {
    final withoutSlashes = lexeme.startsWith('//')
        ? lexeme.substring(2)
        : lexeme;
    final trimmed = withoutSlashes.trim();
    if (trimmed.isEmpty) return null;

    final todoMatch = _todoPattern.firstMatch(trimmed);
    if (todoMatch != null) {
      final body = todoMatch.group(1) ?? '';
      return _isVagueTodo(body) ? 'vague-todo' : null;
    }

    if (_isBannerComment(trimmed)) return 'banner-comment';
    if (_isEmojiOnlyComment(trimmed)) return 'emoji-decoration';
    if (_isEndMarkerComment(trimmed)) return 'end-marker-comment';

    final normalized = _normalizeCommentText(lexeme);
    if (_categoryLabels.contains(normalized)) return 'empty-category-label';

    return null;
  }

  static bool _isBannerComment(String trimmed) {
    if (_pureDividerPattern.hasMatch(trimmed)) return true;
    return _framedLabelPattern.hasMatch(trimmed) &&
        trimmed.contains(RegExp(r'\s'));
  }

  static bool _isEmojiOnlyComment(String trimmed) {
    if (!_emojiPattern.hasMatch(trimmed)) return false;
    final withoutEmoji = trimmed.replaceAll(_emojiPattern, '');
    final residual = withoutEmoji.replaceAll(RegExp(r'[\s!.:,\-]'), '');
    return residual.isEmpty;
  }

  static bool _isEndMarkerComment(String trimmed) {
    final normalized = trimmed.toLowerCase();
    if (normalized == 'end') return true;
    if (!_endMarkerPattern.hasMatch(normalized)) return false;
    final wordCount = normalized.split(RegExp(r'\s+')).length;
    return wordCount <= 4;
  }

  static bool _isVagueTodo(String body) {
    final normalized = body
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[.,:;!]+$'), '')
        .trim();
    return _vagueTodoPhrases.contains(normalized);
  }

  // ---------------------------------------------------------------------------
  // Comment detection (category A)
  // ---------------------------------------------------------------------------

  /// Returns the `//` comment token on the line directly before [node], or
  /// `null` when:
  /// - there is no preceding single-line comment,
  /// - the comment is a `///` Dart-doc comment (never flagged),
  /// - there is a blank line or other code between the comment and [node].
  Token? _immediatelyPrecedingLineComment(AstNode node) {
    final firstToken = node.beginToken;
    final unit = node.root;
    if (unit is! CompilationUnit) return null;
    final lineInfo = unit.lineInfo;

    // Walk the precedingComments chain; track the LAST `//` (not `///`) found.
    // Token.precedingComments is ordered source-first (earliest offset first).
    Token? last;
    Token? comment = firstToken.precedingComments;
    while (comment != null) {
      if (comment.type == TokenType.SINGLE_LINE_COMMENT &&
          !comment.lexeme.startsWith('///')) {
        last = comment;
      }
      comment = comment.next;
    }

    if (last == null) return null;

    // Require the comment to be on the line directly before the first token.
    final commentLine = lineInfo.getLocation(last.offset).lineNumber;
    final nodeLine = lineInfo.getLocation(firstToken.offset).lineNumber;
    if (nodeLine - commentLine != 1) return null;

    return last;
  }

  // ---------------------------------------------------------------------------
  // Normalisation & restatement check (category A)
  // ---------------------------------------------------------------------------

  /// Strips `//`, trims, lowercases, and removes trailing `.,:;!`.
  static String _normalizeCommentText(String lexeme) {
    var text = lexeme;
    if (text.startsWith('//')) text = text.substring(2);
    text = text.trim().toLowerCase();
    while (text.isNotEmpty && '.,:;!'.contains(text[text.length - 1])) {
      text = text.substring(0, text.length - 1).trim();
    }
    return text;
  }

  /// Returns `true` when [normalizedComment] is a trivial restatement of
  /// [normalizedName] (lowercase declaration name) or is in the fixed list.
  ///
  /// The fixed list (`constructor`, `getter`, `setter`, `build method`) covers
  /// the most common AI-slop narrative phrases regardless of the actual
  /// declaration name. The dynamic patterns (`the <name> method/widget`) catch
  /// the "the X method" and "the X widget" variants.
  ///
  /// What this deliberately does NOT match: any comment whose text differs from
  /// the declaration name and is not in the fixed list (informative comments are
  /// never flagged — heuristic quality scoring is out of scope, LLM layer).
  static bool _isNarrativeComment(
    String normalizedComment,
    String normalizedName,
  ) {
    // (a) Exact name match (case-insensitive via both being lowercase).
    if (normalizedComment == normalizedName) return true;

    // (b) Fixed restatement list.
    const fixed = {'constructor', 'getter', 'setter', 'build method'};
    if (fixed.contains(normalizedComment)) return true;

    // (c) "the <name> method" / "the <name> widget" pattern.
    if (normalizedComment == 'the $normalizedName method') return true;
    if (normalizedComment == 'the $normalizedName widget') return true;

    return false;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns the name of the innermost enclosing [ClassDeclaration], or
  /// `'<unknown>'` if none is found.
  ///
  /// Used as part of the qualified name for fingerprint stability.
  // loam-ignore: code-duplicates – identical helper in each rule's private visitor; a shared mixin would couple unrelated rule files together.
  String _enclosingClassName(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is ClassDeclaration) {
        return current.namePart.typeName.lexeme;
      }
      current = current.parent;
    }
    return '<unknown>';
  }
}

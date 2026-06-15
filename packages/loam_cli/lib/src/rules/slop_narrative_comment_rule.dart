import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'generated_file.dart';
import 'rule.dart';

/// Detects `//` comments immediately before a declaration whose normalized text
/// is a trivial restatement of the declaration name or a fixed narrative phrase.
///
/// Rule ID: `slop-narrative-comment`
///
/// A finding is emitted for each single-line `//` comment that appears on the
/// line directly before a class, method, getter/setter, constructor, or
/// top-level function declaration (no blank lines between) and whose normalized
/// text satisfies at least one of:
///
/// 1. **Name-equal** — after stripping `//`, trimming whitespace, and
///    lowercasing, the comment text equals the lowercased declaration name.
/// 2. **Fixed restatement** — the normalized text is in the small, fixed list:
///    `constructor`, `getter`, `setter`, `build method`.
/// 3. **"the NAME method/widget" pattern** — the normalized text equals
///    `the {name} method` or `the {name} widget` where `{name}` is the
///    lowercased declaration name.
///
/// What this rule deliberately does **NOT** catch:
/// - `///` Dart-doc comments — real documentation is never flagged (tabu).
/// - Block comments (`/* */`).
/// - `//` comments whose text is not in the name-equal or fixed-list set —
///   informative `//` comments are never flagged (no heuristic quality
///   scoring; that is the LLM layer, sprint-17).
/// - Comments not immediately adjacent to a declaration (blank line between).
/// - Generated files (`*.g.dart`, `*.freezed.dart`, etc.) — excluded via
///   [isGeneratedDartFile] at the start of each file loop.
///
/// **Semantic anchor (fingerprint stability):**
/// `qualifiedDeclarationName:narrative-comment:occurrenceIndex` — where
/// `qualifiedDeclarationName` is the qualified name (e.g. `MyClass.build`)
/// and `occurrenceIndex` counts prior occurrences of the same qualified name.
/// A pure line shift leaves the anchor unchanged (Invariant 5 / fingerprint
/// semantics).
///
/// **Finding contract:**
/// - `severity`: [Severity.info]
/// - `kind`: `'narrative-comment'`
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

/// AST visitor that collects narrative `//` comments immediately before
/// class/member/function declarations.
class _NarrativeCommentVisitor extends RecursiveAstVisitor<void> {
  _NarrativeCommentVisitor({
    required this.ruleId,
    required this.relativePath,
    required this.findings,
  });

  final String ruleId;
  final String relativePath;
  final List<Finding> findings;

  /// Occurrence counter keyed by qualified declaration name.
  ///
  /// Ensures that multiple narrative comments for declarations with the same
  /// qualified name get distinct, deterministic fingerprints.
  final Map<String, int> _occurrenceCount = {};

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
  // Core check
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
  // Comment detection
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
  // Normalisation & restatement check
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

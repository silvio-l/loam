import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'generated_file.dart';
import 'rule.dart';

/// Detects sequential "workflow narration" comment sequences: two or more
/// `Step N: …` / `First, …` / `Next, …` / `Then, …` / `Finally, …` comments,
/// each immediately preceding a statement in the same function/method/
/// constructor body, that together narrate the body step-by-step even though
/// the statements themselves are already self-explanatory (clear function
/// and variable names).
///
/// Rule ID: `slop-workflow-narration-comment`
///
/// A finding is emitted once **per body** that contains **two or more**
/// single-line `//` comments, each immediately preceding a top-level
/// statement of that body's [Block] (no blank line between comment and
/// statement — same adjacency rule as `slop-narrative-comment`), whose
/// normalized text matches one of:
///
/// - `step <number>` (optionally followed by `:` and more text), e.g.
///   `// Step 1: validate input`.
/// - `first`, `next`, `then`, `finally` as the first word, e.g. `// First,
///   validate the request`, `// Then send the confirmation email`.
///
/// A **single** such comment in a body is not flagged — narrating one step
/// in isolation is common and not evidence of a narrated walkthrough. Only a
/// **sequence** (2+ markers in the same body) triggers a finding, since the
/// slop pattern is the walkthrough structure itself, not any individual
/// comment.
///
/// What this rule deliberately does **NOT** catch:
/// - `///` Dart-doc comments — real documentation is never flagged (tabu).
/// - Block comments (`/* */`).
/// - A single workflow-style comment on its own (no sequence).
/// - Comments not immediately adjacent to the statement they narrate (blank
///   line between).
/// - Nested statement blocks (e.g. inside an `if`/`for` body) — only the
///   body's own top-level statement list is scanned, keeping the "sequence
///   of steps in one function" semantics precise.
/// - Generated files (`*.g.dart`, `*.freezed.dart`, etc.) — excluded via
///   [isGeneratedDartFile] at the start of each file loop.
///
/// **Semantic anchor (fingerprint stability):**
/// `qualifiedMemberName:workflow-narration:occurrenceIndex` — where
/// `qualifiedMemberName` is the qualified name of the enclosing method/
/// function/constructor (e.g. `OrderService.placeOrder`) and
/// `occurrenceIndex` counts prior sequences found for the same qualified
/// name. Unlike the other slop rules, this anchor is deliberately body-level
/// rather than per-comment: the finding describes the whole sequence, not a
/// single declaration or a single comment (Invariant 5 / fingerprint
/// semantics).
///
/// **Finding contract:**
/// - `severity`: [Severity.info]
/// - `kind`: `'workflow-narration'`
/// - `remedy`: imperative fix instruction
/// - `wcagRef`: null (slop rule — no WCAG reference)
///
/// **Suppression:**
/// `// loam-ignore: slop-workflow-narration-comment – <reason>` on or before
/// the line of the *first* comment in the sequence suppresses the finding
/// (the finding is located there).
class SlopWorkflowNarrationCommentRule implements Rule {
  /// The stable rule ID for [SlopWorkflowNarrationCommentRule].
  ///
  /// Exposed as a static constant so callers can filter findings by rule ID
  /// without instantiating the rule or risking a typo.
  static const String ruleIdStatic = 'slop-workflow-narration-comment';

  /// Creates a [SlopWorkflowNarrationCommentRule] rooted at [projectRoot].
  ///
  /// [projectRoot] is the absolute path of the analysed package.
  const SlopWorkflowNarrationCommentRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  final String projectRoot;

  @override
  String get ruleId => 'slop-workflow-narration-comment';

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

      final visitor = _WorkflowNarrationVisitor(
        ruleId: ruleId,
        relativePath: relativePath,
        findings: findings,
      );
      file.result.unit.accept(visitor);
    }

    return findings;
  }
}

/// Matches `step <number>` (optionally with a trailing `:`/text) or one of
/// the fixed sequence-transition words as the first word of the comment.
final RegExp _workflowMarkerPattern = RegExp(
  r'^(step\s+\d+\b|first\b|next\b|then\b|finally\b)',
  caseSensitive: false,
);

/// AST visitor that finds function/method/constructor bodies containing a
/// sequence of workflow-narration comments preceding their statements.
class _WorkflowNarrationVisitor extends RecursiveAstVisitor<void> {
  _WorkflowNarrationVisitor({
    required this.ruleId,
    required this.relativePath,
    required this.findings,
  });

  final String ruleId;
  final String relativePath;
  final List<Finding> findings;

  /// Occurrence counter keyed by qualified member name.
  ///
  /// Ensures that multiple narrated sequences within the same qualified
  /// member (e.g. two local functions with the same enclosing name — rare,
  /// but possible) get distinct, deterministic fingerprints.
  final Map<String, int> _occurrenceCount = {};

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    // loam-ignore: code-duplicates – identical helper in each rule's private visitor; a shared mixin would couple unrelated rule files together.
    final className = _enclosingClassName(node);
    final qualified = '$className.${node.name.lexeme}';
    _checkBody(node.body, qualified);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    if (node.parent is! CompilationUnit) return;
    _checkBody(node.functionExpression.body, node.name.lexeme);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final constructorName = node.name?.lexeme;
    final className = node.typeName?.name ?? _enclosingClassName(node);
    final qualified = constructorName != null
        ? '$className.$constructorName'
        : className;
    _checkBody(node.body, qualified);
    super.visitConstructorDeclaration(node);
  }

  // ---------------------------------------------------------------------------
  // Core check
  // ---------------------------------------------------------------------------

  void _checkBody(FunctionBody body, String qualifiedName) {
    if (body is! BlockFunctionBody) return;
    final statements = body.block.statements;
    if (statements.isEmpty) return;

    final unit = body.root is CompilationUnit
        ? (body.root as CompilationUnit)
        : null;
    if (unit == null) return;

    Token? firstMarkerComment;
    var markerCount = 0;

    for (final statement in statements) {
      final commentToken = _immediatelyPrecedingLineComment(
        statement,
        unit.lineInfo,
      );
      if (commentToken == null) continue;

      final normalized = _normalizeCommentText(commentToken.lexeme);
      if (!_workflowMarkerPattern.hasMatch(normalized)) continue;

      markerCount++;
      firstMarkerComment ??= commentToken;
    }

    // A single narrated step is not evidence of a walkthrough — only a
    // sequence (2+) is the slop pattern this rule targets.
    if (markerCount < 2 || firstMarkerComment == null) return;

    final idx = _occurrenceCount[qualifiedName] ?? 0;
    _occurrenceCount[qualifiedName] = idx + 1;

    final fingerprint = computeFingerprint(
      ruleId: ruleId,
      relativePath: relativePath,
      semanticAnchor: '$qualifiedName:workflow-narration:$idx',
    );

    final location = unit.lineInfo.getLocation(firstMarkerComment.offset);

    findings.add(
      Finding(
        ruleId: ruleId,
        severity: Severity.info,
        filePath: relativePath,
        line: location.lineNumber,
        column: location.columnNumber,
        message:
            'Sequential "Step N:"/"First, …"/"Next, …"/"Then, …"/"Finally, …" '
            'comments narrate this body step-by-step even though the '
            'statements are already self-explanatory.',
        fingerprint: fingerprint,
        kind: 'workflow-narration',
        remedy:
            'Remove the narration comments; if a step genuinely needs '
            'explanation, extract it into a well-named helper function '
            'instead of prefixing it with a step marker, or explain the '
            '*why* rather than the *what*.',
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Comment detection
  // ---------------------------------------------------------------------------

  /// Returns the `//` comment token on the line directly before [node], or
  /// `null` when there is none, it is a `///` Dart-doc comment, or there is a
  /// blank line (or other code) between the comment and [node].
  // loam-ignore: code-duplicates – identical helper in each rule's private visitor; a shared mixin would couple unrelated rule files together.
  Token? _immediatelyPrecedingLineComment(AstNode node, LineInfo lineInfo) {
    final firstToken = node.beginToken;

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

    final commentLine = lineInfo.getLocation(last.offset).lineNumber;
    final nodeLine = lineInfo.getLocation(firstToken.offset).lineNumber;
    if (nodeLine - commentLine != 1) return null;

    return last;
  }

  /// Strips `//`, trims, and lowercases — no trailing-punctuation stripping
  /// needed since [_workflowMarkerPattern] only anchors on the first word(s).
  static String _normalizeCommentText(String lexeme) {
    var text = lexeme;
    if (text.startsWith('//')) text = text.substring(2);
    return text.trim().toLowerCase();
  }

  /// Returns the name of the innermost enclosing [ClassDeclaration], or
  /// `'<unknown>'` if none is found.
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

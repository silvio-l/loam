import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'generated_file.dart';
import 'rule.dart';

/// Detects `catch` blocks whose body is empty or contains only comments.
///
/// Rule ID: `slop-empty-catch`
///
/// A finding is emitted for each [CatchClause] whose [Block] body has
/// **no statements** — covering two cases:
///
/// 1. **Empty body** — `catch (e) {}` — literally nothing between the braces.
/// 2. **Comment-only body** — `catch (e) { // TODO }` — comments are not
///    statements in the Dart AST, so they do not suppress the finding.
///
/// This extends the built-in `empty_catches` lint (which only catches the
/// literal-empty variant) to also flag the comment-only variant that AI agents
/// commonly produce when silencing a catch block with a filler comment.
///
/// What this rule deliberately does **NOT** catch:
/// - Bodies that contain a `rethrow` — rethrow propagates the exception.
/// - Bodies that contain a `throw` — wraps or re-raises the exception.
/// - Bodies that contain a logging call (e.g. `log(e)`, `logger.log(e)`,
///   `print(e)`) — these are all statements; `block.statements.isNotEmpty`
///   ensures they are never reported. This is the conservative allowlist:
///   any statement in the body suppresses the finding.
/// - Generated files (`*.g.dart`, `*.freezed.dart`, etc.) — excluded via
///   [isGeneratedDartFile] at the start of each file loop.
///
/// **Semantic anchor (fingerprint stability):**
/// `enclosingMemberName:catch:occurrenceIndex` — where `enclosingMemberName`
/// is the qualified name of the surrounding function/method, and
/// `occurrenceIndex` counts prior occurrences of the same member name within
/// the same file. A pure line shift (adding blank lines or moving the catch
/// clause) leaves the anchor unchanged (Invariant 5 / fingerprint semantics).
///
/// **Finding contract:**
/// - `severity`: [Severity.warning]
/// - `kind`: `'empty-catch'`
/// - `remedy`: imperative fix instruction
/// - `wcagRef`: null (slop rule — no WCAG reference)
///
/// **Suppression:**
/// `// loam-ignore: slop-empty-catch – <reason>` on or before the line
/// of the offending `catch` suppresses the finding.
///
/// **Abgrenzung:**
/// `empty_catches` (dart lint) → only literal `{}`. `slop-empty-catch` →
/// literal `{}` AND comment-only `{ /* … */ }`.
class SlopEmptyCatchRule implements Rule {
  /// The stable rule ID for [SlopEmptyCatchRule].
  ///
  /// Exposed as a static constant so callers can filter findings by rule ID
  /// without instantiating the rule or risking a typo.
  static const String ruleIdStatic = 'slop-empty-catch';

  /// Creates a [SlopEmptyCatchRule] rooted at [projectRoot].
  ///
  /// [projectRoot] is the absolute path of the analysed package.
  const SlopEmptyCatchRule({required this.projectRoot});

  /// Absolute path of the project being analysed.
  final String projectRoot;

  @override
  String get ruleId => 'slop-empty-catch';

  @override
  RuleCategory get category => RuleCategory.slop;

  @override
  List<Finding> run(ProjectLoadResult result) {
    final findings = <Finding>[];

    for (final file in result.resolved) {
      // Skip generated files — *.g.dart, *.freezed.dart, *.mocks.dart, gen-l10n.
      if (isGeneratedDartFile(file.path)) continue;

      final relativePath = p.relative(file.path, from: projectRoot);

      final visitor = _EmptyCatchVisitor(
        ruleId: ruleId,
        relativePath: relativePath,
        findings: findings,
      );
      file.result.unit.accept(visitor);
    }

    return findings;
  }
}

/// AST visitor that collects empty or comment-only catch clauses.
class _EmptyCatchVisitor extends RecursiveAstVisitor<void> {
  _EmptyCatchVisitor({
    required this.ruleId,
    required this.relativePath,
    required this.findings,
  });

  final String ruleId;
  final String relativePath;
  final List<Finding> findings;

  /// Occurrence counter keyed by `enclosingMemberName:catch`.
  ///
  /// Ensures that multiple flagged catch clauses within the same enclosing
  /// function/method get distinct, deterministic fingerprints.
  final Map<String, int> _occurrenceCount = {};

  @override
  void visitCatchClause(CatchClause node) {
    // Recurse into nested catch clauses first (process inner before outer).
    super.visitCatchClause(node);

    final block = node.body;

    // A catch body is empty-or-comment-only when it has no statements.
    // Comments are not statements in the Dart AST — so both `catch (e) {}`
    // and `catch (e) { // TODO }` satisfy this condition.
    //
    // Conservative allowlist: rethrow, throw, and logging calls all produce at
    // least one statement, so block.statements.isNotEmpty → not reported.
    if (block.statements.isNotEmpty) return;

    _addFinding(node);
  }

  /// Returns the qualified name of the enclosing function or method.
  ///
  /// Used as part of the semantic anchor for fingerprint stability. Walks the
  /// parent chain and returns the first [MethodDeclaration] or
  /// [FunctionDeclaration] name it finds. Returns `'<unknown>'` when no
  /// enclosing member is found (e.g. initialiser in a top-level variable).
  // loam-ignore: code-duplicates – identical helper in each rule's private visitor; a shared mixin would couple unrelated rule files together.
  String _enclosingMemberName(AstNode node) {
    AstNode? current = node.parent;
    while (current != null) {
      if (current is MethodDeclaration) {
        final className =
            (current.parent is ClassDeclaration
                ? (current.parent as ClassDeclaration).namePart.typeName.lexeme
                : null) ??
            '';
        final method = current.name.lexeme;
        return className.isEmpty ? method : '$className.$method';
      }
      if (current is FunctionDeclaration) {
        return current.name.lexeme;
      }
      current = current.parent;
    }
    return '<unknown>';
  }

  /// Emits a finding for the given [node] (a catch clause with an empty body).
  void _addFinding(CatchClause node) {
    final enclosingName = _enclosingMemberName(node);
    final counterKey = '$enclosingName:catch';
    final idx = _occurrenceCount[counterKey] ?? 0;
    _occurrenceCount[counterKey] = idx + 1;

    final anchor = '$enclosingName:catch:$idx';
    final fingerprint = computeFingerprint(
      ruleId: ruleId,
      relativePath: relativePath,
      semanticAnchor: anchor,
    );

    final location = node.offset;
    final lineInfo = node.root is CompilationUnit
        ? (node.root as CompilationUnit).lineInfo
        : null;
    final line = lineInfo?.getLocation(location).lineNumber ?? 1;
    final column = lineInfo?.getLocation(location).columnNumber;

    findings.add(
      Finding(
        ruleId: ruleId,
        severity: Severity.warning,
        filePath: relativePath,
        line: line,
        column: column,
        message:
            'Empty or comment-only `catch` body silently swallows exceptions '
            '— add error handling, rethrow, or a logging call.',
        fingerprint: fingerprint,
        kind: 'empty-catch',
        remedy:
            'Handle the exception: log it (`log(e, stackTrace: st)`), rethrow '
            '(`rethrow`), or wrap it in a domain error (`throw DomainError(e)`). '
            'If swallowing is intentional, suppress with '
            '`// loam-ignore: slop-empty-catch – <reason>`.',
      ),
    );
  }
}

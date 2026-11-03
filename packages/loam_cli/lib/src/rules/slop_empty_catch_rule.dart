import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

import '../loader/project_loader.dart';
import '../model/anchor.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import 'rule.dart';
import 'visit_file.dart';

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
/// The official `empty_catches` lint (package:lints core) already covers the
/// literal `{}`; loam adds the comment-only/TODO body that AI agents commonly
/// produce, and it runs as part of the project-wide gate with baseline and
/// ratchet.
///
/// What this rule deliberately does **NOT** catch:
/// - `catch (_) {}` and `on X catch (_) {}` with a literally empty body — the
///   wildcard is Dart's explicit "ignored on purpose" marker (the official
///   `empty_catches` lint treats it the same way). A comment between the
///   braces, a named parameter (`catch (e) {}`) or `catch (_, st) {}` still
///   count as findings.
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
/// `enclosingMemberName:catch:contentHash:n` — where `enclosingMemberName`
/// is the qualified name of the surrounding function/method, `contentHash`
/// covers the catch clause's normalised tokens (`on X catch (e, s) {}`;
/// comments and formatting ignored) and `n` counts only earlier identical
/// clauses in the same member. Inserting other catch clauses or code before it,
/// or re-formatting, leaves the anchor unchanged.
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
/// literal `{}` with a named parameter AND comment-only `{ /* … */ }`.
class SlopEmptyCatchRule implements FileRule {
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
  List<Finding> run(ProjectLoadResult result) => runPerFile(this, result);

  @override
  List<Finding> runFile(LoadedFile file) => visitFile(
    file,
    projectRoot,
    (relativePath, findings) => _EmptyCatchVisitor(
      ruleId: ruleId,
      relativePath: relativePath,
      findings: findings,
    ),
  );
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

  final AnchorCounter _anchors = AnchorCounter();

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

    // `catch (_) {}` is the explicit "ignored on purpose" marker. A comment in
    // the braces turns it back into a finding (comment-only body).
    if (_isIntentionalIgnore(node)) return;

    _addFinding(node);
  }

  /// `true` for `catch (_) {}` / `on X catch (_) {}`: a wildcard exception
  /// parameter, no stack trace parameter and not a single comment in the body.
  static bool _isIntentionalIgnore(CatchClause node) {
    if (node.exceptionParameter?.name.lexeme != '_') return false;
    if (node.stackTraceParameter != null) return false;
    return node.body.rightBracket.precedingComments == null;
  }

  /// Emits a finding for the given [node] (a catch clause with an empty body).
  void _addFinding(CatchClause node) {
    final enclosingName = enclosingMemberName(node);
    final anchor = _anchors.next(
      '$enclosingName:catch',
      normalizedSource(node),
    );
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
            'If swallowing is intentional, write `catch (_) {}` (the wildcard '
            'marks it as deliberate) or suppress with '
            '`// loam-ignore: slop-empty-catch – <reason>`.',
      ),
    );
  }
}

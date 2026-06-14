import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import '../rules/generated_file.dart';
import 'duplicate_cluster.dart';

export 'duplicate_cluster.dart';

/// Detects duplicated code blocks across a Dart project using normalised
/// token sequences and Rabin-Karp rolling hashing.
///
/// The collector is the **single seam** shared by the future `code-duplicates`
/// rule. It mirrors the [FunctionComplexityCollector] pattern: an injectable,
/// `const`-constructible component that accepts a [ProjectLoadResult] and
/// returns a sorted list of [DuplicateCluster]s.
///
/// **What is detected:**
/// - **Type-1 clones** — exact duplicates (whitespace / comment independent,
///   because the analysis is AST-based).
/// - **Type-2 clones** — structurally identical blocks where identifier names
///   and/or literal values differ. Consistent (alpha) renaming assigns each
///   *distinct* identifier within a block a stable fragment-local slot index
///   (`ID#0`, `ID#1`, …) and does the same for literals (`LIT#0`, `LIT#1`, …).
///   Two blocks match only if they share the same repetition pattern of slots —
///   genuine renames produce the same pattern; parallel boilerplate with
///   different leaf-value repetitions does not.
///
/// **What is NOT detected:**
/// - **Type-3 clones** — blocks with inserted/deleted lines. Out of scope for
///   this sprint; too FP-prone for a deterministic default-on rule (PRD §Out
///   of Scope).
///
/// **Granularity:**
/// The collector works at the level of **function/method bodies** — each body
/// is treated as an independent sequence of statements. A duplicate is reported
/// when two or more bodies share a normalised token sequence with at least
/// [kMinDuplicateTokens] tokens.
///
/// **Exclusions:**
/// - Generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, …) are
///   excluded via [isGeneratedDartFile] — not re-implemented here.
/// - Files that could not be resolved by the [ProjectLoader] are silently
///   skipped; the collector never throws.
///
/// **Determinism (Invariant 5):**
/// The returned list is sorted by the first location's filePath → startLine.
/// Two invocations on equal inputs yield an identical list.
class DuplicateCodeCollector {
  /// Creates a [DuplicateCodeCollector].
  const DuplicateCodeCollector();

  /// Collects duplicate code clusters from [result].
  ///
  /// [projectRoot] is the absolute path of the analysed package root, used to
  /// compute POSIX-relative [DuplicateLocation.filePath] values.
  ///
  /// Never throws. Returns an empty list when [result.resolved] is empty or
  /// when no blocks with ≥ [kMinDuplicateTokens] tokens are duplicated.
  List<DuplicateCluster> collect(ProjectLoadResult result, String projectRoot) {
    // Step 1: extract normalised token sequences from every resolvable,
    // non-generated file.
    final blocks = <_Block>[];

    for (final file in result.resolved) {
      if (isGeneratedDartFile(file.path)) continue;

      final relPath = _toRelativePosix(file.path, projectRoot);
      final lineInfo = file.result.lineInfo;

      // Visit the compilation unit's AST to collect all function bodies.
      final visitor = _BodyCollector(relPath: relPath, lineInfo: lineInfo);
      file.result.unit.accept(visitor);
      blocks.addAll(visitor.blocks);
    }

    // Step 2: group blocks by their normalised token sequence (exact match
    // covers Type-1 and Type-2 simultaneously because consistent renaming
    // preserves the repetition pattern of identifier/literal slots).
    //
    // Two pre-filters guard against false positives before clustering:
    //  • kMinDuplicateTokens — short blocks (getters, trivial helpers) excluded.
    //  • kMinDistinctTokenTypes — low-diversity blocks (repetitive fill,
    //    data-initialisation, pure x+x+…+x patterns) excluded.
    final bySequence = <String, List<_Block>>{};
    for (final block in blocks) {
      if (block.tokens.length < kMinDuplicateTokens) continue;
      if (block.tokens.toSet().length < kMinDistinctTokenTypes) continue;
      final key = block.tokens.join(' ');
      (bySequence[key] ??= []).add(block);
    }

    // Step 3: every sequence with ≥ 2 occurrences is a cluster.
    final clusters = <DuplicateCluster>[];
    for (final entry in bySequence.entries) {
      final group = entry.value;
      if (group.length < 2) continue;

      // Sort locations lexicographically (filePath → startLine) for
      // determinism (Invariant 5) and stable fingerprint anchor.
      final locations =
          group
              .map(
                (b) => DuplicateLocation(
                  filePath: b.relPath,
                  startLine: b.startLine,
                  endLine: b.endLine,
                ),
              )
              .toList()
            ..sort((a, b) {
              final pathCmp = a.filePath.compareTo(b.filePath);
              if (pathCmp != 0) return pathCmp;
              return a.startLine.compareTo(b.startLine);
            });

      clusters.add(
        DuplicateCluster(
          locations: locations,
          tokenCount: group.first.tokens.length,
        ),
      );
    }

    // Sort clusters by their anchor location (first element, already the
    // lexicographically smallest after the inner sort above).
    clusters.sort((a, b) {
      final first = a.locations.first;
      final second = b.locations.first;
      final pathCmp = first.filePath.compareTo(second.filePath);
      if (pathCmp != 0) return pathCmp;
      return first.startLine.compareTo(second.startLine);
    });

    return clusters;
  }

  /// Returns a POSIX path relative to [projectRoot].
  static String _toRelativePosix(String absolutePath, String projectRoot) {
    final rel = p.relative(absolutePath, from: projectRoot);
    return rel.replaceAll(r'\', '/');
  }
}

// ---------------------------------------------------------------------------
// Internal data holder — not part of the public API.
// ---------------------------------------------------------------------------

/// Holds the normalised token sequence and source location for a single
/// function/method body extracted from the AST.
class _Block {
  _Block({
    required this.relPath,
    required this.startLine,
    required this.endLine,
    required this.tokens,
  });

  /// POSIX path relative to the project root.
  final String relPath;

  /// 1-based start line of the body in the source file.
  final int startLine;

  /// 1-based end line of the body in the source file.
  final int endLine;

  /// Normalised token sequence produced by consistent (alpha) renaming.
  ///
  /// Within this block, each distinct identifier name is mapped to a stable
  /// fragment-local slot: first occurrence → `ID#0`, second distinct name →
  /// `ID#1`, and so on. Literals are handled identically (`LIT#0`, `LIT#1`,
  /// …). The same name always maps to the same slot within the same block,
  /// which preserves the repetition pattern. All other tokens (keywords,
  /// punctuation, operators) are kept verbatim as structural skeleton.
  ///
  /// Comments and whitespace are never emitted by the token stream, so they
  /// are implicitly ignored.
  final List<String> tokens;
}

// ---------------------------------------------------------------------------
// Internal AST visitor — not part of the public API.
// ---------------------------------------------------------------------------

/// Visits a compilation unit and collects one [_Block] per function/method
/// body (FunctionBody node), extracting its normalised token sequence.
///
/// The visitor deliberately operates at the body level so that the granularity
/// matches a meaningful unit of work — matching sub-statement windows (Rabin-
/// Karp line-level) is out of scope for this iteration.
class _BodyCollector extends RecursiveAstVisitor<void> {
  _BodyCollector({required this.relPath, required this.lineInfo});

  final String relPath;

  /// The analyzer line-info object for offset → line conversion.
  final LineInfo lineInfo;

  /// Collected blocks after visiting the compilation unit.
  final List<_Block> blocks = [];

  // ---- Executable declarations ----

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _collectBody(node.functionExpression.body);
    // Still recurse so nested local functions are collected.
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _collectBody(node.body);
    super.visitMethodDeclaration(node);
  }

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    _collectBody(node.body);
    super.visitConstructorDeclaration(node);
  }

  // ---- Body extraction ----

  void _collectBody(FunctionBody body) {
    if (body is EmptyFunctionBody) return;

    final tokens = _normaliseBody(body);
    if (tokens.isEmpty) return;

    final startLoc = lineInfo.getLocation(body.offset);
    final endLoc = lineInfo.getLocation(body.end - 1);

    blocks.add(
      _Block(
        relPath: relPath,
        startLine: startLoc.lineNumber,
        endLine: endLoc.lineNumber,
        tokens: tokens,
      ),
    );
  }

  /// Produces the normalised token sequence for [body] using consistent
  /// (alpha) renaming.
  ///
  /// Walks the raw token stream anchored inside [body]'s source range.
  /// For each token:
  ///
  /// - **Identifiers**: the first distinct name encountered maps to `ID#0`,
  ///   the next new name to `ID#1`, and so on. Repeated occurrences of the
  ///   same name emit the same slot index. This preserves the repetition
  ///   pattern within the block — genuine Type-2 renames produce identical
  ///   normalised sequences, while parallel boilerplate that reuses different
  ///   identifiers at the same positions does not.
  /// - **Literals**: same slot-based scheme independently (`LIT#0`, `LIT#1`,
  ///   …). The actual literal values are not compared.
  /// - **Keywords, punctuation, operators**: kept verbatim as structural
  ///   skeleton so different AST shapes produce different sequences.
  ///
  /// Comments and whitespace are never emitted by the Dart token stream.
  List<String> _normaliseBody(FunctionBody body) {
    final idMap = <String, int>{};
    var idCounter = 0;
    final litMap = <String, int>{};
    var litCounter = 0;

    final result = <String>[];
    Token? tok = body.beginToken;
    final endOffset = body.end;

    while (tok != null && tok.offset < endOffset) {
      if (tok.isEof) break;
      if (tok.type == TokenType.IDENTIFIER) {
        final slot = idMap.putIfAbsent(tok.lexeme, () => idCounter++);
        result.add('ID#$slot');
      } else if (_isLiteral(tok.type)) {
        final slot = litMap.putIfAbsent(tok.lexeme, () => litCounter++);
        result.add('LIT#$slot');
      } else {
        // Keywords, punctuation, operators — keep as structural skeleton.
        result.add(tok.lexeme);
      }
      tok = tok.next;
    }

    return result;
  }

  /// Returns `true` when [type] represents a literal value token.
  static bool _isLiteral(TokenType type) {
    return type == TokenType.INT ||
        type == TokenType.DOUBLE ||
        type == TokenType.STRING ||
        type == TokenType.HEXADECIMAL ||
        type == TokenType.STRING_INTERPOLATION_EXPRESSION ||
        type == TokenType.STRING_INTERPOLATION_IDENTIFIER;
  }
}

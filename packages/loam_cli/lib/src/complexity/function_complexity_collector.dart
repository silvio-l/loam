import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import '../rules/generated_file.dart';
import 'complexity_calculator.dart';
import 'function_complexity.dart';

export 'function_complexity.dart';

/// Collects complexity measurements for every named executable in a Dart
/// package's `lib/` tree.
///
/// The collector is the **single source of truth** shared by the
/// `function-complexity` rule and the health-score module. Running the
/// collector once and sharing the result guarantees that both consumers see
/// identical numbers — no drift.
///
/// **What is enumerated:**
/// - Top-level functions.
/// - Named and unnamed (`.new`) constructors — implicit default constructors
///   are skipped (they have no body and no user-written complexity).
/// - Methods (instance and static).
/// - Getters and setters with a non-trivial body (expression-body or block).
///   Getters/setters with an [EmptyFunctionBody] (abstract declarations) are
///   skipped.
///
/// **What is NOT enumerated:**
/// - Local functions and closures (their complexity flows into the enclosing
///   executable via [ComplexityCalculator]).
/// - Declarations in generated files (`*.g.dart`, `*.freezed.dart`,
///   `*.mocks.dart`, Flutter gen-l10n output).
/// - Declarations in files outside `lib/` (e.g. `bin/`, `test/`, `tool/`).
///
/// **Part/augment handling:**
/// The element model's `libraryElement.fragments` is used instead of naive
/// per-file iteration. Each library file is visited exactly once; its
/// fragments include any `part` files. The part-file AST nodes are resolved
/// via [ProjectLoadResult.partUnits], preventing double-counting.
///
/// **Robustness:**
/// A non-empty [ProjectLoadResult.errors] does not cause a crash; the
/// collector measures all resolvable files and silently skips unresolvable
/// ones.
///
/// **Determinism:**
/// The returned list is sorted by `filePath`, then `line`, then
/// `qualifiedName`. Two invocations on equal inputs yield an identical list.
class FunctionComplexityCollector {
  /// Creates a [FunctionComplexityCollector].
  const FunctionComplexityCollector({
    this.calculator = const ComplexityCalculator(),
  });

  /// The calculator used to measure each executable body.
  final ComplexityCalculator calculator;

  /// Collects complexity measurements for all named executables in the
  /// `lib/` files of [result].
  ///
  /// [projectRoot] is the absolute path of the analysed package root, used
  /// to compute POSIX-relative [FunctionComplexity.filePath] values.
  ///
  /// Never throws. Returns an empty list when [result.resolved] is empty.
  List<FunctionComplexity> collect(
    ProjectLoadResult result,
    String projectRoot,
  ) {
    // Build a path → ResolvedUnitResult map covering both library files and
    // part files so the AST of every fragment is reachable.
    final unitByPath = <String, ResolvedUnitResult>{};
    for (final file in result.resolved) {
      unitByPath[file.path] = file.result;
    }
    for (final partUnit in result.partUnits) {
      unitByPath[partUnit.path] = partUnit;
    }

    final findings = <FunctionComplexity>[];

    // Guard: deduplicate by element id so that augmented declarations (which
    // can appear in multiple fragments) are never counted twice.
    final seenIds = <int>{};

    for (final file in result.resolved) {
      if (!file.isUnderLib) continue;
      if (isGeneratedDartFile(file.path)) continue;

      final library = file.result.libraryElement;

      // Walk every fragment of the library (fragment 0 = library file itself;
      // fragment 1+ = part/augment files). This ensures that declarations in
      // part files are collected even though they are not standalone entries
      // in ProjectLoadResult.resolved.
      for (final fragment in library.fragments) {
        final fragmentPath = fragment.source.fullName;

        // Skip generated part files (e.g. *.g.dart included via `part`).
        if (isGeneratedDartFile(fragmentPath)) continue;

        // Obtain the ResolvedUnitResult for this fragment's source file.
        // If the unit is not in our map (e.g. the file had errors and was not
        // resolved), skip this fragment gracefully.
        final unitResult = unitByPath[fragmentPath];
        if (unitResult == null) continue;

        final relPath = _toRelativePosix(fragmentPath, projectRoot);
        final lineInfo = unitResult.lineInfo;

        // Walk the AST of this fragment's compilation unit to enumerate
        // executables. We use the AST visitor approach so we can accurately
        // determine which executables to measure (including those we skip,
        // like abstract methods) and obtain the correct FunctionBody.
        final visitor = _ExecutableVisitor(
          calculator: calculator,
          relPath: relPath,
          lineInfo: lineInfo,
          seenIds: seenIds,
          results: findings,
        );
        unitResult.unit.accept(visitor);
      }
    }

    // Deterministic sort: filePath → line → qualifiedName.
    // Satisfies the reproducibility invariant (Invariant 5).
    findings.sort((a, b) {
      final pathCmp = a.filePath.compareTo(b.filePath);
      if (pathCmp != 0) return pathCmp;
      final lineCmp = a.line.compareTo(b.line);
      if (lineCmp != 0) return lineCmp;
      return a.qualifiedName.compareTo(b.qualifiedName);
    });

    return findings;
  }

  /// Returns a POSIX path relative to [projectRoot].
  static String _toRelativePosix(String absolutePath, String projectRoot) {
    final rel = p.relative(absolutePath, from: projectRoot);
    return rel.replaceAll(r'\', '/');
  }
}

// ---------------------------------------------------------------------------
// Internal AST visitor — not part of the public API.
// ---------------------------------------------------------------------------

/// Visits all top-level and member-level executable declarations in a single
/// [CompilationUnit] and records a [FunctionComplexity] for each.
///
/// **Enumeration rules:**
/// - Top-level [FunctionDeclaration]: always included (if not a local
///   function, which cannot appear at top-level anyway).
/// - [ClassDeclaration], [MixinDeclaration], [EnumDeclaration],
///   [ExtensionDeclaration]: recurse into members.
/// - [MethodDeclaration] (method, getter, setter): included unless the body
///   is [EmptyFunctionBody] (abstract/interface declarations have no
///   complexity).
/// - [ConstructorDeclaration]: included unless synthetic (no source offset
///   for the name) or the body is [EmptyFunctionBody] with no explicit
///   declaration.
/// - Local functions ([FunctionDeclarationStatement]) and closures
///   ([FunctionExpression]): NOT added as separate entries — their
///   complexity flows into the enclosing metric via [ComplexityCalculator].
///
/// The visitor does NOT recurse into [FunctionDeclarationStatement] or
/// [FunctionExpression] bodies as top-level enumerables — but
/// [ComplexityCalculator] DOES traverse them when computing the enclosing
/// body's score.
class _ExecutableVisitor extends RecursiveAstVisitor<void> {
  _ExecutableVisitor({
    required this.calculator,
    required this.relPath,
    required this.lineInfo,
    required this.seenIds,
    required this.results,
  });

  final ComplexityCalculator calculator;
  final String relPath;
  final LineInfo lineInfo;
  final Set<int> seenIds;
  final List<FunctionComplexity> results;

  // The qualified name prefix set when we enter a class/mixin/enum/extension.
  String? _enclosingName;

  // ---- Top-level functions -------------------------------------------------

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    // Only process top-level function declarations (not local functions, which
    // appear inside FunctionDeclarationStatement and should not be collected).
    if (node.parent is! CompilationUnit) return;

    final element = node.declaredFragment?.element;
    if (element == null) return;
    if (!seenIds.add(element.id)) return;

    final name = node.name.lexeme;
    final body = node.functionExpression.body;

    // Skip empty bodies (abstract — shouldn't appear at top level, but guard).
    if (body is EmptyFunctionBody) return;

    final loc = lineInfo.getLocation(node.name.offset);
    results.add(
      FunctionComplexity(
        qualifiedName: name,
        filePath: relPath,
        line: loc.lineNumber,
        metrics: calculator.calculate(body),
      ),
    );
    // Do NOT recurse into the function body for separate local-function entries.
    // ComplexityCalculator handles closures internally.
  }

  // ---- Class / Mixin / Enum / Extension -----------------------------------

  @override
  void visitClassDeclaration(ClassDeclaration node) {
    final saved = _enclosingName;
    _enclosingName = node.namePart.typeName.lexeme;
    // Recurse into members (the super call visits the class body).
    super.visitClassDeclaration(node);
    _enclosingName = saved;
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    final saved = _enclosingName;
    _enclosingName = node.name.lexeme;
    super.visitMixinDeclaration(node);
    _enclosingName = saved;
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    final saved = _enclosingName;
    _enclosingName = node.namePart.typeName.lexeme;
    super.visitEnumDeclaration(node);
    _enclosingName = saved;
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    final saved = _enclosingName;
    // Anonymous extensions have no name; use a fallback so the enclosing
    // context is set but the member qualified name is still stable via the
    // method name alone (rare edge case).
    _enclosingName = node.name?.lexeme ?? '<extension>';
    super.visitExtensionDeclaration(node);
    _enclosingName = saved;
  }

  // ---- Methods, getters, setters ------------------------------------------

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    final body = node.body;
    // Skip abstract/interface declarations (no real complexity).
    if (body is EmptyFunctionBody) return;

    final element = node.declaredFragment?.element;
    if (element == null) return;
    if (!seenIds.add(element.id)) return;

    final enclosing = _enclosingName ?? '<unknown>';
    // Append `=` for setter declarations to disambiguate from a getter with
    // the same property name (e.g. `Calculator.value` vs `Calculator.value=`).
    final baseName = node.name.lexeme;
    final memberName = node.isSetter ? '$baseName=' : baseName;
    final qualifiedName = '$enclosing.$memberName';

    final loc = lineInfo.getLocation(node.name.offset);
    results.add(
      FunctionComplexity(
        qualifiedName: qualifiedName,
        filePath: relPath,
        line: loc.lineNumber,
        metrics: calculator.calculate(body),
      ),
    );
    // Do NOT recurse into the body — ComplexityCalculator handles the interior.
  }

  // ---- Constructors --------------------------------------------------------

  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    final body = node.body;
    // Skip constructors with no body at all (implicit/abstract redirects with
    // EmptyFunctionBody have zero complexity and are not worth enumerating).
    if (body is EmptyFunctionBody) return;

    final element = node.declaredFragment?.element;
    if (element == null) return;

    // Skip implicit default constructors (no user-written body).
    if (element.isOriginImplicitDefault) return;

    if (!seenIds.add(element.id)) return;

    final enclosing = _enclosingName ?? '<unknown>';
    // Unnamed constructors are represented with the stable key `ClassName.new`.
    final ctorName = node.name?.lexeme;
    final qualifiedName = (ctorName == null || ctorName.isEmpty)
        ? '$enclosing.new'
        : '$enclosing.$ctorName';

    // Use the constructor name token offset if available; fall back to the
    // class-name identifier (typeName) for unnamed constructors.
    final nameOffset = node.name?.offset ?? node.typeName?.offset ?? 0;

    final loc = lineInfo.getLocation(nameOffset);
    results.add(
      FunctionComplexity(
        qualifiedName: qualifiedName,
        filePath: relPath,
        line: loc.lineNumber,
        metrics: calculator.calculate(body),
      ),
    );
    // Do NOT recurse.
  }

  // ---- Prevent local-function/closure double-counting ---------------------

  /// Override to prevent local functions declared inside a function body from
  /// being collected as separate top-level executables.
  ///
  /// Their complexity is captured by the enclosing [ComplexityCalculator] call.
  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    // Intentionally do NOT call super — local functions are not separate
    // executables from the collector's perspective.
  }

  /// Override to prevent closure expressions from being collected.
  ///
  /// Closures' complexity is captured by the enclosing [ComplexityCalculator].
  @override
  void visitFunctionExpression(FunctionExpression node) {
    // Only prevent recursion for closure expressions that appear *inside* a
    // method/function body. Top-level FunctionDeclaration uses a
    // FunctionExpression as its body container — those are visited via
    // visitFunctionDeclaration above, not here.
    // We check: if the parent is a FunctionDeclaration that is itself a direct
    // child of CompilationUnit, let visitFunctionDeclaration handle it.
    final parent = node.parent;
    if (parent is FunctionDeclaration && parent.parent is CompilationUnit) {
      return; // Top-level function — handled by visitFunctionDeclaration.
    }
    // Otherwise, this is a closure/lambda — do NOT recurse.
  }
}

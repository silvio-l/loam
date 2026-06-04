import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';

/// A candidate public top-level symbol for the `unused-public-exports` rule.
class PublicApiCandidate {
  const PublicApiCandidate({
    required this.element,
    required this.relativePath,
    required this.kind,
    required this.line,
  });

  /// The resolved element for this symbol.
  final Element element;

  /// POSIX path relative to the project root.
  final String relativePath;

  /// Human-readable kind label (e.g. `class`, `function`, `enum`).
  final String kind;

  /// 1-based line number of the declaration.
  final int line;

  /// The unqualified name of the symbol.
  String get name => element.name ?? '<unknown>';
}

/// Collects public top-level declarations under `lib/` as candidates for the
/// `unused-public-exports` rule (Slice A — Top-Level only).
///
/// Conservative exclusions applied:
/// - Private symbols (name starts with `_`).
/// - Generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`).
/// - `main` functions (entrypoints must never be reported as unused).
/// - Symbols annotated with `@visibleForTesting`.
/// - Symbols in libraries that re-export them via `export` directives
///   (re-exported symbols are part of the public API).
class PublicApiCollector {
  const PublicApiCollector();

  /// Collects all public top-level candidates from `lib/` files in [result].
  ///
  /// [projectRoot] is the absolute path of the analysed package root. It is
  /// used to compute [PublicApiCandidate.relativePath].
  List<PublicApiCandidate> collect(
    ProjectLoadResult result,
    String projectRoot,
  ) {
    final candidates = <PublicApiCandidate>[];

    // Build the set of element ids that are re-exported anywhere in the project.
    final reExported = _collectReExportedElements(result);

    for (final file in result.resolved) {
      if (!file.isUnderLib) continue;
      if (_isGeneratedFile(file.path)) continue;

      final unit = file.result.unit;
      final lineInfo = file.result.lineInfo;
      final relPath = _toRelativePosix(file.path, projectRoot);

      for (final decl in unit.declarations) {
        final element = _elementOfDeclaration(decl);
        if (element == null) continue;

        final name = element.name ?? '';
        if (name.startsWith('_')) continue; // private
        if (name == 'main') continue; // entrypoint
        if (_hasConservativeAnnotation(element)) continue;
        if (reExported.contains(element.id)) continue;

        final kind = _kindLabel(decl);
        final offset = decl.offset;
        final loc = lineInfo.getLocation(offset);

        candidates.add(
          PublicApiCandidate(
            element: element,
            relativePath: relPath,
            kind: kind,
            line: loc.lineNumber,
          ),
        );
      }
    }

    return candidates;
  }

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns true for `*.g.dart`, `*.freezed.dart`, `*.mocks.dart`.
  static bool _isGeneratedFile(String path) {
    final basename = p.basename(path);
    return basename.endsWith('.g.dart') ||
        basename.endsWith('.freezed.dart') ||
        basename.endsWith('.mocks.dart');
  }

  /// Returns true when [element] carries a conservative annotation that marks
  /// intentional public exposure: `@visibleForTesting`.
  static bool _hasConservativeAnnotation(Element element) {
    for (final annotation in element.metadata.annotations) {
      if (annotation.isVisibleForTesting) return true;
    }
    return false;
  }

  /// Collects all element ids that are re-exported via `export` directives in
  /// any resolved file. A re-exported symbol is part of the public API and must
  /// not be reported as unused.
  Set<int> _collectReExportedElements(ProjectLoadResult result) {
    final ids = <int>{};
    for (final file in result.resolved) {
      final library = file.result.libraryElement;
      for (final exported in library.exportedLibraries) {
        for (final c in exported.classes) {
          ids.add(c.id);
        }
        for (final fn in exported.topLevelFunctions) {
          ids.add(fn.id);
        }
        for (final e in exported.enums) {
          ids.add(e.id);
        }
        for (final mixin in exported.mixins) {
          ids.add(mixin.id);
        }
        for (final ext in exported.extensions) {
          ids.add(ext.id);
        }
        for (final typedef in exported.typeAliases) {
          ids.add(typedef.id);
        }
        for (final v in exported.topLevelVariables) {
          ids.add(v.id);
        }
        for (final g in exported.getters) {
          ids.add(g.id);
        }
        for (final s in exported.setters) {
          ids.add(s.id);
        }
      }
    }
    return ids;
  }

  /// Returns the primary [Element] for a top-level [Declaration].
  static Element? _elementOfDeclaration(Declaration decl) {
    if (decl is ClassDeclaration) return decl.declaredFragment?.element;
    if (decl is MixinDeclaration) return decl.declaredFragment?.element;
    if (decl is EnumDeclaration) return decl.declaredFragment?.element;
    if (decl is ExtensionDeclaration) return decl.declaredFragment?.element;
    if (decl is FunctionDeclaration) return decl.declaredFragment?.element;
    if (decl is TypeAlias) return decl.declaredFragment?.element;
    if (decl is TopLevelVariableDeclaration) {
      final variables = decl.variables.variables;
      if (variables.isEmpty) return null;
      final fragment = variables.first.declaredFragment;
      if (fragment is TopLevelVariableFragment) return fragment.element;
      return null;
    }
    return null;
  }

  /// Human-readable kind label for a declaration node.
  static String _kindLabel(Declaration decl) {
    if (decl is ClassDeclaration) return 'class';
    if (decl is MixinDeclaration) return 'mixin';
    if (decl is EnumDeclaration) return 'enum';
    if (decl is ExtensionDeclaration) return 'extension';
    if (decl is FunctionDeclaration) return 'function';
    if (decl is TopLevelVariableDeclaration) return 'variable';
    if (decl is TypeAlias) return 'typedef';
    return 'declaration';
  }

  /// Returns a POSIX path relative to [projectRoot].
  static String _toRelativePosix(String absolutePath, String projectRoot) {
    final rel = p.relative(absolutePath, from: projectRoot);
    return rel.replaceAll(r'\', '/');
  }
}

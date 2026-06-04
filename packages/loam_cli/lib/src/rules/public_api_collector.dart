import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
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
///
/// **Part-file handling:** The [ProjectLoader] skips `part` files as
/// standalone resolved entries (they are not libraries). This collector
/// therefore traverses `libraryElement.fragments` for every resolved library
/// file, which covers declarations in the library file itself (fragment 0)
/// as well as declarations in each `part` file (fragment 1+). Deduplication
/// is based on element identity (`element.id`), so each symbol yields
/// exactly one candidate regardless of how many fragments the library has.
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

    // Deduplicate by element id: an element can only appear in one fragment,
    // but defensive guard prevents any accidental double-visits.
    final seenIds = <int>{};

    // Build the set of element ids that are re-exported anywhere in the project.
    final reExported = _collectReExportedElements(result);

    for (final file in result.resolved) {
      if (!file.isUnderLib) continue;

      final library = file.result.libraryElement;

      // Walk every fragment of the library (fragment 0 = the library file
      // itself; fragment 1+ = part files). This ensures that declarations in
      // part files are collected even though part files do not appear as
      // standalone entries in ProjectLoadResult.resolved.
      for (final fragment in library.fragments) {
        final fragmentPath = fragment.source.fullName;

        // Skip generated part files (e.g. *.g.dart included via `part`).
        if (_isGeneratedFile(fragmentPath)) continue;

        final relPath = _toRelativePosix(fragmentPath, projectRoot);
        final lineInfo = fragment.lineInfo;

        // Collect each declaration kind from this fragment.
        _visitFragmentDeclarations(
          fragment: fragment,
          relPath: relPath,
          lineInfo: lineInfo,
          reExported: reExported,
          seenIds: seenIds,
          candidates: candidates,
        );
      }
    }

    return candidates;
  }

  // ---------------------------------------------------------------------------
  // Fragment traversal
  // ---------------------------------------------------------------------------

  void _visitFragmentDeclarations({
    required LibraryFragment fragment,
    required String relPath,
    required LineInfo lineInfo,
    required Set<int> reExported,
    required Set<int> seenIds,
    required List<PublicApiCandidate> candidates,
  }) {
    // Classes (including ClassDeclaration and ClassTypeAlias)
    for (final f in fragment.classes) {
      _addIfEligible(
        element: f.element,
        kind: 'class',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }

    // Enums
    for (final f in fragment.enums) {
      _addIfEligible(
        element: f.element,
        kind: 'enum',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }

    // Mixins
    for (final f in fragment.mixins) {
      _addIfEligible(
        element: f.element,
        kind: 'mixin',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }

    // Extensions
    for (final f in fragment.extensions) {
      _addIfEligible(
        element: f.element,
        kind: 'extension',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }

    // Top-level functions
    for (final f in fragment.functions) {
      _addIfEligible(
        element: f.element,
        kind: 'function',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }

    // Typedefs (type aliases)
    for (final f in fragment.typeAliases) {
      _addIfEligible(
        element: f.element,
        kind: 'typedef',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }

    // Top-level variables: only explicit declarations (const/var/final x = …),
    // NOT the synthetic backing variable for an explicit getter/setter pair.
    for (final f in fragment.topLevelVariables) {
      if (!f.element.isOriginDeclaration) continue;
      _addIfEligible(
        element: f.element,
        kind: 'variable',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }

    // Explicit top-level getters (`int get foo => …`).
    // We use the underlying PropertyInducingElement (variable) as the
    // canonical element to match UsageIndex._canonical.
    for (final f in fragment.getters) {
      // Only explicit getter declarations — skip synthetic getters
      // auto-generated for variable declarations.
      if (!f.element.isOriginDeclaration) continue;
      final canonicalElement = f.element.variable;
      _addIfEligible(
        element: canonicalElement,
        kind: 'getter',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }

    // Explicit top-level setters (`set foo(x) {…}`).
    for (final f in fragment.setters) {
      if (!f.element.isOriginDeclaration) continue;
      final canonicalElement = f.element.variable;
      // seenIds guards against a getter+setter pair reporting the same
      // canonical variable element twice.
      _addIfEligible(
        element: canonicalElement,
        kind: 'setter',
        nameOffset: f.nameOffset,
        relPath: relPath,
        lineInfo: lineInfo,
        reExported: reExported,
        seenIds: seenIds,
        candidates: candidates,
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Eligibility check & candidate creation
  // ---------------------------------------------------------------------------

  void _addIfEligible({
    required Element element,
    required String kind,
    required int? nameOffset,
    required String relPath,
    required LineInfo lineInfo,
    required Set<int> reExported,
    required Set<int> seenIds,
    required List<PublicApiCandidate> candidates,
  }) {
    final name = element.name ?? '';
    if (name.isEmpty) return;
    if (name.startsWith('_')) return; // private
    if (name == 'main') return; // entrypoint
    if (_hasConservativeAnnotation(element)) return;
    if (reExported.contains(element.id)) return;

    // Deduplicate: use element id as canonical key.
    // This ensures a symbol shared across a getter+setter pair (or appearing
    // in multiple fragments) is added at most once.
    if (!seenIds.add(element.id)) return;

    final offset = nameOffset ?? 0;
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

  /// Returns a POSIX path relative to [projectRoot].
  static String _toRelativePosix(String absolutePath, String projectRoot) {
    final rel = p.relative(absolutePath, from: projectRoot);
    return rel.replaceAll(r'\', '/');
  }
}

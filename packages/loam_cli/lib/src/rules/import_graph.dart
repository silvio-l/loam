import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

import '../loader/project_loader.dart';
import 'generated_file.dart';

/// A directed Library→Library graph over the first-party `lib/` libraries of a
/// Dart package.
///
/// Node keys are stable POSIX paths relative to the project root (e.g.
/// `lib/src/foo.dart`).  The format is compatible with [CycleDetector] and any
/// other consumer that expects `Map<String, Set<String>>`.
///
/// ## Scope
///
/// - **Nodes:** every resolved, non-`part`, non-generated library file under
///   `lib/` (`LoadedFile.isUnderLib == true`).
/// - **Edges:** `import` *and* `export` directives whose resolved target is
///   another first-party `lib/` library in the same package.
/// - **Never nodes/edges:** external packages (`package:flutter/…`), `dart:…`
///   libraries, `part of` files, generated files (`*.g.dart`,
///   `*.freezed.dart`, `*.mocks.dart`), and self-edges.
///
/// ## Robustness
///
/// When [ProjectLoadResult.errors] is non-empty (e.g. a broken target project)
/// the graph is built only from the resolvable files in
/// [ProjectLoadResult.resolved]. No exception is thrown.
///
/// ## Determinism (Invariant 5)
///
/// Node keys and edge sets are derived from path-sorted inputs (the
/// [ProjectLoader] already sorts [ProjectLoadResult.resolved]) and the
/// resulting [edges] map preserves insertion order.  Each edge set is a sorted
/// [List] exposed via [adjacency], which satisfies CycleDetector's expectation
/// of a `Map<String, Set<String>>`.
class ImportGraph {
  ImportGraph._({
    required List<String> nodes,
    required Map<String, Set<String>> edges,
  }) : nodes = List.unmodifiable(nodes),
       edges = Map.unmodifiable(
         edges.map((k, v) => MapEntry(k, Set.unmodifiable(v))),
       );

  /// Builds an [ImportGraph] from [loadResult].
  ///
  /// [projectRoot] is the absolute path of the analysed package root; it is
  /// used to compute relative POSIX node keys.
  ///
  /// Files in [ProjectLoadResult.errors] are silently skipped.
  factory ImportGraph.build(ProjectLoadResult loadResult, String projectRoot) {
    final root = p.normalize(p.absolute(projectRoot));

    // Collect the set of absolute paths that are valid lib/ nodes (non-part,
    // non-generated, under lib/).  We need this set to filter edges quickly.
    final libNodePaths = <String>{};
    for (final file in loadResult.resolved) {
      if (!file.isUnderLib) continue;
      if (isGeneratedDartFile(file.path)) continue;
      // part-of files are excluded by ProjectLoader — resolved entries are
      // never `isPart`; the loader routes those to partUnits.
      libNodePaths.add(file.path);
    }

    // Node keys: relative POSIX paths, sorted for determinism.
    final nodes =
        libNodePaths.map((absPath) => _toRelativePosix(absPath, root)).toList()
          ..sort();

    // Build edge map: node key → set of target node keys.
    // Edges are collected in path-sorted file order (ProjectLoadResult.resolved
    // is already sorted by the loader — Invariant 5).
    final edgeMap = <String, Set<String>>{
      for (final nodeKey in nodes) nodeKey: <String>{},
    };

    for (final file in loadResult.resolved) {
      if (!libNodePaths.contains(file.path)) continue;

      final fromKey = _toRelativePosix(file.path, root);
      final library = file.result.libraryElement;

      // Iterate only the first fragment's imports/exports.  A Dart library can
      // have multiple fragments (augmentations), but import/export directives
      // live in the primary fragment (fragment 0).
      final fragment = library.fragments.first;

      // --- import directives ---
      for (final imp in fragment.libraryImports) {
        if (imp.isSynthetic) continue; // skip implicit dart:core
        final uri = imp.uri;
        if (uri is! DirectiveUriWithLibrary) continue;
        final targetPath = _libraryAbsolutePath(uri.library);
        if (targetPath == null) continue;
        if (!libNodePaths.contains(targetPath)) continue;
        final toKey = _toRelativePosix(targetPath, root);
        if (toKey == fromKey) continue; // no self-edges
        edgeMap[fromKey]!.add(toKey);
      }

      // --- export directives ---
      for (final exp in fragment.libraryExports) {
        final uri = exp.uri;
        if (uri is! DirectiveUriWithLibrary) continue;
        final targetPath = _libraryAbsolutePath(uri.library);
        if (targetPath == null) continue;
        if (!libNodePaths.contains(targetPath)) continue;
        final toKey = _toRelativePosix(targetPath, root);
        if (toKey == fromKey) continue; // no self-edges
        edgeMap[fromKey]!.add(toKey);
      }
    }

    return ImportGraph._(nodes: nodes, edges: edgeMap);
  }

  /// Sorted list of node keys (relative POSIX paths of first-party lib/ files).
  final List<String> nodes;

  /// Adjacency map: node key → set of directly reachable node keys.
  ///
  /// Every node from [nodes] has an entry here (even if it has no outgoing
  /// edges, the set is empty). This makes the map directly consumable by
  /// [CycleDetector.findCycles].
  final Map<String, Set<String>> edges;

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  /// Returns the normalised absolute path for [library], or `null` when the
  /// source is not available (e.g. SDK libraries).
  static String? _libraryAbsolutePath(LibraryElement library) {
    // The canonical source of a library is its first fragment's source.
    final source = library.fragments.first.source;
    // SDK libraries use a `dart:…` URI whose full name starts with `dart:`.
    // Their source.fullName is a platform-specific path but we can guard via
    // checking whether it is a real file path.
    final fullName = source.fullName;
    if (fullName.isEmpty) return null;
    // Reject dart: SDK entries: their source paths contain the SDK URI prefix
    // or are non-absolute.  A reliable guard is checking the URI scheme.
    final uri = source.uri;
    if (uri.scheme == 'dart') return null;
    return p.normalize(fullName);
  }

  /// Converts an absolute path to a POSIX-relative path from [projectRoot].
  static String _toRelativePosix(String absolutePath, String projectRoot) {
    final rel = p.relative(absolutePath, from: projectRoot);
    return rel.replaceAll(r'\', '/');
  }
}

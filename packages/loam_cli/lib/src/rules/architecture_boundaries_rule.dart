import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:path/path.dart' as p;

import '../config/architecture_config.dart';
import '../loader/project_loader.dart';
import '../model/finding.dart';
import '../model/fingerprint.dart';
import '../model/project_path.dart';
import 'import_graph.dart';
import 'rule.dart';

/// Reports `import` edges that violate the configured **Boundaries**.
///
/// Rule ID: `architecture-boundaries`
///
/// The rule reads only the materialised architecture from `loam.yaml`
/// (`layers:` + `boundaries:`, written by `loam init`, see issue #16); it
/// never detects layers itself. Without configured boundaries it emits
/// nothing, so it is inert in a zero-config run.
///
/// Only `import` directives are checked: `export` directives are not, so a
/// re-export is not treated as a dependency edge by this rule.
///
/// Edges come from the shared [ImportGraph] (first-party `lib/` libraries,
/// `import` directives only, no generated or `part` files), so the rule sees
/// exactly the dependencies the `circular-dependencies` rule sees.
///
/// A file belongs to the layer whose directory is its longest path prefix;
/// files outside every layer, and edges inside one layer, are never reported.
///
/// Finding semantics:
/// - **Location:** the first `import` directive of the importing file that
///   resolves to the forbidden target (line of the directive).
/// - **Message:** names source layer, target layer and both files.
/// - **Fingerprint:** importing file + `<from>-><to>:<target file>`; stable
///   against line shifts, one finding per forbidden file-to-file edge.
/// - **Severity:** [Severity.warning], like the other drift rules.
///
/// Suppression and baseline work through the central pipeline layer
/// (`// loam-ignore: architecture-boundaries`, `loam.yaml` rule toggle).
class ArchitectureBoundariesRule implements Rule {
  /// Creates the rule for [projectRoot] with the configured [layers]
  /// (name -> project-relative directory) and [boundaries].
  const ArchitectureBoundariesRule({
    required this.projectRoot,
    required this.layers,
    required this.boundaries,
  });

  /// Absolute path of the project being analysed.
  final String projectRoot;

  /// Layer name -> project-relative POSIX directory.
  final Map<String, String> layers;

  /// Forbidden edges between layers.
  final List<LayerBoundary> boundaries;

  @override
  String get ruleId => 'architecture-boundaries';

  @override
  RuleCategory get category => RuleCategory.drift;

  @override
  List<Finding> run(ProjectLoadResult result) {
    if (boundaries.isEmpty || layers.isEmpty) return const [];

    final denied = <String, Set<String>>{};
    for (final b in boundaries) {
      denied.putIfAbsent(b.from, () => <String>{}).addAll(b.deny);
    }

    final graph = ImportGraph.build(result, projectRoot);
    final root = p.normalize(p.absolute(projectRoot));
    final layerOf = _LayerLookup(layers);

    // Forbidden edges first (cheap, graph only); AST is read only for the
    // files that actually have one, to find the directive line.
    final violations = <String, Map<String, ({String from, String to})>>{};
    for (final entry in graph.edges.entries) {
      final fromLayer = layerOf(entry.key);
      final deniedTargets = fromLayer == null ? null : denied[fromLayer];
      if (deniedTargets == null) continue;
      for (final target in entry.value) {
        final toLayer = layerOf(target);
        if (toLayer == null || toLayer == fromLayer) continue;
        if (!deniedTargets.contains(toLayer)) continue;
        violations.putIfAbsent(entry.key, () => {})[target] = (
          from: fromLayer!,
          to: toLayer,
        );
      }
    }
    if (violations.isEmpty) return const [];

    final findings = <Finding>[];
    for (final file in result.resolved) {
      final filePath = projectRelativePosixPath(file.path, root);
      final forbidden = violations[filePath];
      if (forbidden == null) continue;

      final lines = _firstImportLines(file, root);
      for (final target in forbidden.keys.toList()..sort()) {
        final layer = forbidden[target]!;
        findings.add(
          Finding(
            ruleId: ruleId,
            severity: Severity.warning,
            filePath: filePath,
            line: lines[target] ?? 1,
            message:
                'forbidden dependency [kind=layer-boundary-violation]: layer '
                '"${layer.from}" must not import layer "${layer.to}" '
                '($filePath imports $target)',
            fingerprint: computeFingerprint(
              ruleId: ruleId,
              relativePath: filePath,
              semanticAnchor: '${layer.from}->${layer.to}:$target',
            ),
            kind: 'layer-boundary-violation',
            remedy:
                'This import breaks a boundary declared in loam.yaml '
                '(`${layer.from}` must not depend on `${layer.to}`); it is a '
                'real architecture violation, not a style preference. Do not '
                'move or re-export the file to hide the edge. Invert the '
                'dependency: put the shared contract (an abstract class or '
                'interface) into a layer that `${layer.from}` may import and '
                'let `${layer.to}` implement it, or pass the value in from '
                'the caller. If the boundary itself is wrong, change it in '
                'loam.yaml deliberately and say so in the commit.',
          ),
        );
      }
    }
    return findings;
  }

  /// Target path -> line of the first `import` directive of [file] resolving
  /// to it.
  Map<String, int> _firstImportLines(LoadedFile file, String root) {
    final lines = <String, int>{};
    final lineInfo = file.parsed.lineInfo;
    for (final directive in file.result.unit.directives) {
      if (directive is! ImportDirective) continue;
      final uri = directive.libraryImport?.uri;
      if (uri is! DirectiveUriWithLibrary) continue;
      final source = uri.library.firstFragment.source;
      if (source.uri.scheme == 'dart' || source.fullName.isEmpty) continue;
      final target = projectRelativePosixPath(
        p.normalize(source.fullName),
        root,
      );
      lines.putIfAbsent(
        target,
        () => lineInfo.getLocation(directive.offset).lineNumber,
      );
    }
    return lines;
  }
}

/// Maps a project-relative path to the layer with the longest matching
/// directory prefix, or `null` when no layer contains it.
class _LayerLookup {
  _LayerLookup(Map<String, String> layers)
    : _byLength = (layers.entries.toList()
        ..sort((a, b) => b.value.length.compareTo(a.value.length)));

  final List<MapEntry<String, String>> _byLength;

  String? call(String path) {
    for (final e in _byLength) {
      final dir = e.value.endsWith('/')
          ? e.value.substring(0, e.value.length - 1)
          : e.value;
      if (path == dir || path.startsWith('$dir/')) return e.key;
    }
    return null;
  }
}

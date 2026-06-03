import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:path/path.dart' as p;

/// A successfully resolved Dart file entry produced by [ProjectLoader].
///
/// Carries the full [ResolvedUnitResult] (element model reachable via
/// [ResolvedUnitResult.libraryElement]), the normalised absolute [path], and
/// the [isUnderLib] flag that distinguishes `lib/` surface from
/// `bin/`/`test/`/`tool/` files.
class LoadedFile {
  const LoadedFile({
    required this.result,
    required this.path,
    required this.isUnderLib,
  });

  /// The fully resolved unit — [libraryElement] and the complete element model
  /// are accessible from here.
  final ResolvedUnitResult result;

  /// Normalised absolute path of the Dart source file.
  final String path;

  /// `true` when [path] is under the package's `lib/` directory.
  final bool isUnderLib;
}

/// The outcome of a [ProjectLoader.load] call.
///
/// Resolved files are in [resolved]; files that could not be resolved (e.g.
/// orphaned part files, SDK errors) are in [errors]. In healthy projects
/// [errors] is empty.
class ProjectLoadResult {
  const ProjectLoadResult({required this.resolved, required this.errors});

  /// Successfully resolved files (non-empty element model guaranteed).
  final List<LoadedFile> resolved;

  /// Per-file error entries — file paths for which [ResolvedUnitResult] could
  /// not be obtained. Dedicated error mapping is Slice 02.
  final List<String> errors;
}

/// Loads a Dart package from [projectRoot] and resolves all Dart source files
/// found under `lib/`, `bin/`, `test/`, and `tool/`.
///
/// Uses the `analyzer` package's [AnalysisContextCollection] to build a full
/// element model — no String/Regex heuristics (Invariant 1: Semantics before
/// syntax).
///
/// This component has **no knowledge** of the rule/output/CLI layer —
/// it is the pure semantic loading layer.
class ProjectLoader {
  const ProjectLoader();

  /// Loads the Dart package at [projectRoot] and resolves all Dart files.
  ///
  /// Never throws in normal operation. Files that cannot be resolved are
  /// collected in [ProjectLoadResult.errors].
  Future<ProjectLoadResult> load(String projectRoot) async {
    final root = p.normalize(p.absolute(projectRoot));
    final dartFiles = _collectDartFiles(root);

    if (dartFiles.isEmpty) {
      return const ProjectLoadResult(resolved: [], errors: []);
    }

    final collection = AnalysisContextCollection(includedPaths: [root]);
    try {
      final resolved = <LoadedFile>[];
      final errors = <String>[];

      final libDir = p.join(root, 'lib') + p.separator;

      for (final filePath in dartFiles) {
        final session = collection.contextFor(filePath).currentSession;
        final someResult = await session.getResolvedUnit(filePath);

        if (someResult is ResolvedUnitResult) {
          resolved.add(
            LoadedFile(
              result: someResult,
              path: filePath,
              isUnderLib: filePath.startsWith(libDir),
            ),
          );
        } else {
          errors.add(filePath);
        }
      }

      return ProjectLoadResult(resolved: resolved, errors: errors);
    } finally {
      await collection.dispose();
    }
  }

  /// Collects absolute normalised paths of all `*.dart` files under the
  /// standard source directories of a Dart package.
  List<String> _collectDartFiles(String root) {
    const sourceDirs = ['lib', 'bin', 'test', 'tool'];
    final files = <String>[];

    for (final dir in sourceDirs) {
      final directory = Directory(p.join(root, dir));
      if (!directory.existsSync()) continue;
      for (final entity in directory.listSync(recursive: true)) {
        if (entity is File && entity.path.endsWith('.dart')) {
          files.add(p.normalize(entity.absolute.path));
        }
      }
    }

    return files;
  }
}

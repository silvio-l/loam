import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
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

/// A file that could not be successfully loaded by [ProjectLoader].
///
/// Carries the normalised absolute [path] of the file and a human-readable
/// [reason] explaining why it was not resolved (e.g. parse errors, invalid
/// path, or other analysis failures).
class LoadFileError {
  const LoadFileError({required this.path, required this.reason});

  /// Normalised absolute path of the Dart source file that failed to load.
  final String path;

  /// Human-readable explanation of why this file could not be loaded.
  final String reason;
}

/// The outcome of a [ProjectLoader.load] call.
///
/// Resolved files are in [resolved]; files that could not be resolved (e.g.
/// files with parse/semantic errors, orphaned part files, SDK errors) are in
/// [errors]. In healthy projects [errors] is empty.
class ProjectLoadResult {
  const ProjectLoadResult({required this.resolved, required this.errors});

  /// Successfully resolved files (non-empty element model guaranteed).
  final List<LoadedFile> resolved;

  /// Per-file error entries — files for which a clean [ResolvedUnitResult]
  /// could not be obtained. Each entry carries the file path and a
  /// human-readable reason.
  final List<LoadFileError> errors;
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
///
/// The loader **never throws** in normal operation. All failures are mapped to
/// typed [LoadFileError] entries in [ProjectLoadResult.errors]:
/// - If the project root does not exist, a single root-level error is returned.
/// - If a file returns [InvalidResult] from the analyzer, it is recorded as an
///   error with the result type name as reason.
/// - If a file resolves but has diagnostics of severity [Severity.error], it
///   is recorded as an error with the first error diagnostic message as reason.
class ProjectLoader {
  const ProjectLoader();

  /// Loads the Dart package at [projectRoot] and resolves all Dart files.
  ///
  /// Never throws. Files that cannot be cleanly resolved are collected in
  /// [ProjectLoadResult.errors]. If the root does not exist, returns a result
  /// with a single root-level [LoadFileError] and an empty resolved list.
  Future<ProjectLoadResult> load(String projectRoot) async {
    final root = p.normalize(p.absolute(projectRoot));

    // Guard: non-existent project root — return typed error, do not crash.
    if (!Directory(root).existsSync()) {
      return ProjectLoadResult(
        resolved: const [],
        errors: [
          LoadFileError(
            path: root,
            reason: 'Project root does not exist: $root',
          ),
        ],
      );
    }

    final dartFiles = _collectDartFiles(root);

    if (dartFiles.isEmpty) {
      return const ProjectLoadResult(resolved: [], errors: []);
    }

    final collection = AnalysisContextCollection(includedPaths: [root]);
    try {
      final resolved = <LoadedFile>[];
      final errors = <LoadFileError>[];

      final libDir = p.join(root, 'lib') + p.separator;

      for (final filePath in dartFiles) {
        final session = collection.contextFor(filePath).currentSession;
        final someResult = await session.getResolvedUnit(filePath);

        if (someResult is ResolvedUnitResult) {
          // Check for parse/semantic errors: files with error-severity
          // diagnostics are mapped to the error branch so downstream rules
          // never receive a broken element model.
          final firstError = _firstErrorDiagnostic(someResult.diagnostics);

          if (firstError == null) {
            // Clean resolution — add to the success branch.
            resolved.add(
              LoadedFile(
                result: someResult,
                path: filePath,
                isUnderLib: filePath.startsWith(libDir),
              ),
            );
          } else {
            // Has parse/semantic errors — add to the error branch.
            errors.add(
              LoadFileError(path: filePath, reason: firstError.message),
            );
          }
        } else {
          // InvalidResult (e.g. InvalidPathResult, NotLibraryButPartResult) —
          // the file cannot be resolved at all.
          errors.add(
            LoadFileError(
              path: filePath,
              reason: someResult.runtimeType.toString(),
            ),
          );
        }
      }

      return ProjectLoadResult(resolved: resolved, errors: errors);
    } finally {
      await collection.dispose();
    }
  }

  /// Returns the first [Diagnostic] with [Severity.error] from [diagnostics],
  /// or `null` if none exist.
  Diagnostic? _firstErrorDiagnostic(List<Diagnostic> diagnostics) {
    for (final d in diagnostics) {
      if (d.severity == Severity.error) return d;
    }
    return null;
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

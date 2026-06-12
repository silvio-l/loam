import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:path/path.dart' as p;

import 'sdk_locator.dart';
import 'stack_profile.dart';
export 'stack_profile.dart';

/// A successfully resolved Dart file entry produced by [ProjectLoader].
///
/// Carries the full [ResolvedUnitResult] (element model reachable via
/// [ResolvedUnitResult.libraryElement]), the normalised absolute [path], and
/// the [isUnderLib] flag that distinguishes `lib/` surface from
/// `bin/`/`test/`/`tool/` files.
class LoadedFile {
  /// Creates a [LoadedFile].
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
  /// Creates a [LoadFileError] for [path] with the given [reason].
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
///
/// Part-file compilation units are in [partUnits]. Part files (`part of …`)
/// are NOT standalone library entries — their declarations are reachable
/// through [LoadedFile.result.libraryElement.fragments] of the owning library
/// and must not be re-collected as candidates. However, *references* inside
/// part files (e.g. a static field accessed as `ClassName.field` inside a
/// `part of` file) must be visible to the reference index so that they are not
/// incorrectly reported as unused. [partUnits] provides those compilation units
/// for reference-scanning only.
///
/// The [stackProfile] is derived from the project's `pubspec.yaml` by
/// [ProjectLoader] during loading. It is a read-only diagnostic object —
/// never used for suppression decisions (Invariant 1).
class ProjectLoadResult {
  /// Creates a [ProjectLoadResult].
  const ProjectLoadResult({
    required this.resolved,
    required this.errors,
    this.partUnits = const [],
    this.stackProfile = const StackProfile.empty(),
  });

  /// Successfully resolved files (non-empty element model guaranteed).
  final List<LoadedFile> resolved;

  /// Per-file error entries — files for which a clean [ResolvedUnitResult]
  /// could not be obtained. Each entry carries the file path and a
  /// human-readable reason.
  final List<LoadFileError> errors;

  /// Resolved compilation units for `part of` files.
  ///
  /// Part files are not standalone library entries (they are not libraries),
  /// so their declarations are NOT re-collected as candidates. They are stored
  /// here exclusively so the [UsageIndex] can scan their AST for *references*
  /// to symbols declared elsewhere — preventing False Positives when a symbol
  /// is referenced only from a part file.
  final List<ResolvedUnitResult> partUnits;

  /// Read-only stack metadata derived from `pubspec.yaml`.
  ///
  /// Defaults to [StackProfile.empty()] when pubspec is missing or unparseable.
  /// Feeds the `stack: …` diagnostic line and future registry priming.
  /// **Never** used for suppression decisions.
  final StackProfile stackProfile;
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
/// The loader **never throws for analysis failures** — per-file parse/semantic
/// problems are mapped to typed [LoadFileError] entries (see below). The single
/// exception is a missing environment: when no usable Dart SDK can be located,
/// [load] throws [SdkResolutionException] (a precondition failure, not a
/// per-file failure — without an SDK every file would fail identically). It
/// carries a ready-to-print, actionable message; callers surface it on stderr.
///
/// All analysis failures are mapped to typed [LoadFileError] entries in
/// [ProjectLoadResult.errors]:
/// - If the project root does not exist, a single root-level error is returned.
/// - If a file returns [InvalidResult] from the analyzer, it is recorded as an
///   error with the result type name as reason.
/// - If a file resolves but has diagnostics of severity [Severity.error], it
///   is recorded as an error with the first error diagnostic message as reason.
class ProjectLoader {
  /// Creates a [ProjectLoader].
  const ProjectLoader();

  /// Loads the Dart package at [projectRoot] and resolves all Dart files.
  ///
  /// Never throws. Files that cannot be cleanly resolved are collected in
  /// [ProjectLoadResult.errors]. If the root does not exist, returns a result
  /// with a single root-level [LoadFileError] and an empty resolved list.
  ///
  /// The returned [ProjectLoadResult.stackProfile] is always populated from
  /// `pubspec.yaml` (defensive: missing/broken pubspec ⇒ [StackProfile.empty()]).
  Future<ProjectLoadResult> load(String projectRoot) async {
    final root = p.normalize(p.absolute(projectRoot));

    // Parse pubspec.yaml defensively — always done, even when root is missing
    // or the project has no Dart files (the profile is always available).
    final stackProfile = StackProfile.fromProjectRoot(root);

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
        stackProfile: stackProfile,
      );
    }

    final dartFiles = _collectDartFiles(root);

    if (dartFiles.isEmpty) {
      return ProjectLoadResult(
        resolved: const [],
        errors: const [],
        stackProfile: stackProfile,
      );
    }

    // Pass an explicitly resolved SDK path so the analyzer works both on the
    // Dart VM (pub install) and as a compiled AOT binary (Homebrew), where no
    // SDK sits beside the executable.
    //
    // Validate the path up front: handing the analyzer a non-SDK directory
    // (e.g. a Flutter checkout root, when only flutter/bin is on PATH) makes
    // AnalysisContextCollection's construction throw a raw PathNotFoundException
    // — opaque noise for humans and AI agents. Fail with an actionable,
    // steering message instead (set DART_SDK → bin/cache/dart-sdk).
    final sdkPath = resolveDartSdkPath();
    if (sdkPath == null || !isUsableDartSdk(sdkPath)) {
      throw SdkResolutionException.notFound(resolved: sdkPath);
    }

    final AnalysisContextCollection collection;
    try {
      collection = AnalysisContextCollection(
        includedPaths: [root],
        sdkPath: sdkPath,
      );
    } on FileSystemException {
      // Belt-and-suspenders: a path that passed the lib/_internal check but is
      // still incomplete (truncated/corrupt SDK) surfaces here. Convert the raw
      // analyzer crash into the same actionable, stacktrace-free guidance.
      throw SdkResolutionException.notFound(resolved: sdkPath);
    }
    try {
      final resolved = <LoadedFile>[];
      final errors = <LoadFileError>[];
      final partUnits = <ResolvedUnitResult>[];

      final libDir = p.join(root, 'lib') + p.separator;

      for (final filePath in dartFiles) {
        // contextFor throws StateError when [filePath] belongs to a nested
        // package that has its own pubspec.yaml and is therefore not part of
        // the enclosing AnalysisContextCollection. Treat as a load error so
        // the rule layer never receives a broken/incomplete element model, but
        // the loader still processes all other files cleanly.
        SomeResolvedUnitResult someResult;
        try {
          final session = collection.contextFor(filePath).currentSession;
          someResult = await session.getResolvedUnit(filePath);
        } on StateError catch (e) {
          errors.add(LoadFileError(path: filePath, reason: e.message));
          continue;
        }

        if (someResult is ResolvedUnitResult) {
          // A `part of` file resolves as a ResolvedUnitResult with isPart=true.
          // Its declarations are reachable through the owning library's
          // libraryElement.fragments and must NOT be re-collected as candidates.
          // However, its compilation unit IS stored in [partUnits] so the
          // UsageIndex can scan it for *references* — preventing False Positives
          // when a symbol is only referenced from a part file (HellerIO FP #2).
          if (someResult.isPart) {
            // Only store clean part units for reference scanning; broken part
            // files cannot contribute reliable reference data.
            if (_firstErrorDiagnostic(someResult.diagnostics) == null) {
              partUnits.add(someResult);
            }
            continue;
          }

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

      // Invariant 5 (Reproduzierbarkeit): sort both lists by normalised
      // absolute path so that two runs over the same codebase always yield
      // identical order — independent of the AnalysisContextCollection's
      // unspecified iteration order.
      resolved.sort((a, b) => a.path.compareTo(b.path));
      errors.sort((a, b) => a.path.compareTo(b.path));
      partUnits.sort((a, b) => a.path.compareTo(b.path));

      return ProjectLoadResult(
        resolved: resolved,
        errors: errors,
        partUnits: partUnits,
        stackProfile: stackProfile,
      );
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

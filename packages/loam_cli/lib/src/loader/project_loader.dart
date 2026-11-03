import 'dart:io';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/diagnostic/diagnostic.dart';
import 'package:path/path.dart' as p;

import '../progress/progress_sink.dart';
import '../timing/phase_timer.dart';
import 'analyzer_cache.dart';
import 'sdk_locator.dart';
import 'stack_profile.dart';
export 'stack_profile.dart';

/// A successfully loaded Dart file entry produced by [ProjectLoader].
///
/// In a full load it carries the resolved unit ([result], element model
/// reachable via [ResolvedUnitResult.libraryElement]); in a parse-only load
/// ([ProjectLoader.load] with `parseOnly: true`) only the [parsed] unit. Both
/// carry the normalised absolute [path] and the [isUnderLib] flag that
/// distinguishes `lib/` surface from `bin/`/`test/`/`tool/` files.
class LoadedFile {
  /// Creates a [LoadedFile] for a resolved unit.
  const LoadedFile({
    required ResolvedUnitResult result,
    required this.path,
    required this.isUnderLib,
  }) : _result = result,
       parsed = result;

  /// Creates a [LoadedFile] for a parse-only load: [result] is unavailable.
  const LoadedFile.parsed({
    required this.parsed,
    required this.path,
    required this.isUnderLib,
  }) : _result = null;

  /// The unit's AST, content and line info — available in every load.
  /// `FileRule`s and the suppression scan read only this.
  final ParsedUnitResult parsed;

  final ResolvedUnitResult? _result;

  /// The fully resolved unit — [libraryElement] and the complete element model
  /// are accessible from here. Throws [StateError] in a parse-only load, which
  /// the runner only uses when every active rule is a `FileRule`.
  ResolvedUnitResult get result =>
      _result ??
      (throw StateError(
        '$path was only parsed, not resolved (parse-only load)',
      ));

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
  /// Test seam: one analyzer store for all projects a test file loads, so the
  /// SDK summaries are built once instead of once per temporary project. Used
  /// only when a load names no store of its own; entries are keyed by content
  /// signature, so sharing never changes results. Production code never sets it.
  static String? testCacheDirectory;

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
  ///
  /// [progressSink] receives semantic progress events: `startPhase` once (with
  /// the total dart-file count), `advance` per file, and `endPhase` on exit.
  /// Defaults to [NoopProgressSink] — callers that do not want progress pass
  /// nothing and get zero overhead.
  ///
  /// [cacheDirectory]: when set, the analyzer keeps its summary store there
  /// between runs ([AnalyzerCache]); results are identical, the resolve phase
  /// is faster on a warm store. If the store cannot be opened or the load
  /// with it fails, the project is loaded again without it.
  ///
  /// When no [cacheDirectory] is given, [testCacheDirectory] stands in for it.
  ///
  /// [parseOnly]: when `true`, files are only parsed, not resolved. Entries
  /// then carry [LoadedFile.parsed] only, [ProjectLoadResult.partUnits] stays
  /// empty, and only syntax errors put a file into [ProjectLoadResult.errors].
  /// For runs whose rules all read nothing but the file's own AST.
  Future<ProjectLoadResult> load(
    String projectRoot, {
    ProgressSink progressSink = const NoopProgressSink(),
    String? cacheDirectory,
    bool parseOnly = false,
  }) async {
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

    final timer = PhaseTimer.active;
    final stopSetup = timer?.begin('setup');
    final dartFiles = _collectDartFiles(root);

    if (dartFiles.isEmpty) {
      stopSetup?.call();
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

    Future<ProjectLoadResult> loadWith(
      AnalysisContextCollection Function() create,
    ) async {
      final AnalysisContextCollection collection;
      try {
        collection = create();
      } on FileSystemException {
        // Belt-and-suspenders: a path that passed the lib/_internal check but
        // is still incomplete (truncated/corrupt SDK) surfaces here. Convert
        // the raw analyzer crash into the same actionable, stacktrace-free
        // guidance.
        throw SdkResolutionException.notFound(resolved: sdkPath);
      }
      stopSetup?.call();
      return _loadFiles(
        collection,
        root: root,
        dartFiles: dartFiles,
        stackProfile: stackProfile,
        progressSink: progressSink,
        parseOnly: parseOnly,
      );
    }

    // The summary store only speeds up resolution; a parse-only load does not
    // need it.
    final storeDirectory = cacheDirectory ?? testCacheDirectory;
    final cache = parseOnly || storeDirectory == null
        ? null
        : AnalyzerCache.open(storeDirectory);
    if (cache != null) {
      var failed = false;
      try {
        return await loadWith(
          () => cache.collection(includedPaths: [root], sdkPath: sdkPath),
        );
      } on SdkResolutionException {
        rethrow;
      } on Object catch (error) {
        // Anything going wrong with the store must not end the run: fall
        // through and load once more without it, exactly as before #8. The
        // store is discarded so a broken entry does not make every later run
        // load twice.
        failed = true;
        timer?.begin('cache-fallback')();
        progressSink.notice(
          'loam: analyzer cache failed (${error.runtimeType}); discarded '
          '$storeDirectory, this run continues without it.',
        );
      } finally {
        await cache.close(discard: failed);
      }
    }
    return loadWith(
      () => AnalysisContextCollection(includedPaths: [root], sdkPath: sdkPath),
    );
  }

  Future<ProjectLoadResult> _loadFiles(
    AnalysisContextCollection collection, {
    required String root,
    required List<String> dartFiles,
    required StackProfile stackProfile,
    required ProgressSink progressSink,
    required bool parseOnly,
  }) async {
    final stopResolve = PhaseTimer.active?.begin(
      parseOnly ? 'parse' : 'resolve',
      detail: '${dartFiles.length} files',
    );
    // Start progress phase — we now know the total file count.
    progressSink.startPhase('Lade Projekt', total: dartFiles.length);
    try {
      final resolved = <LoadedFile>[];
      final errors = <LoadFileError>[];
      final partUnits = <ResolvedUnitResult>[];

      final libDir = p.join(root, 'lib') + p.separator;

      for (final filePath in dartFiles) {
        // Wrap per-file processing in try/finally so advance() is always called
        // — even when the loop body exits via `continue` (e.g. StateError or
        // part-file early-exit). The finally runs before the continue.
        try {
          // contextFor throws StateError when [filePath] belongs to a nested
          // package that has its own pubspec.yaml and is therefore not part of
          // the enclosing AnalysisContextCollection. Treat as a load error so
          // the rule layer never receives a broken/incomplete element model, but
          // the loader still processes all other files cleanly.
          final Object someResult;
          try {
            final session = collection.contextFor(filePath).currentSession;
            someResult = parseOnly
                ? session.getParsedUnit(filePath)
                : await session.getResolvedUnit(filePath);
          } on StateError catch (e) {
            errors.add(LoadFileError(path: filePath, reason: e.message));
            continue;
          }

          if (someResult is ParsedUnitResult) {
            // A `part of` file resolves as a ResolvedUnitResult with isPart=true.
            // Its declarations are reachable through the owning library's
            // libraryElement.fragments and must NOT be re-collected as candidates.
            // However, its compilation unit IS stored in [partUnits] so the
            // UsageIndex can scan it for *references* — preventing False Positives
            // when a symbol is only referenced from a part file (HellerIO FP #2).
            // A parse-only load needs no reference index and drops parts.
            if (someResult.isPart) {
              // Only store clean part units for reference scanning; broken part
              // files cannot contribute reliable reference data.
              if (someResult is ResolvedUnitResult &&
                  _firstErrorDiagnostic(someResult.diagnostics) == null) {
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
              final isUnderLib = filePath.startsWith(libDir);
              resolved.add(
                someResult is ResolvedUnitResult
                    ? LoadedFile(
                        result: someResult,
                        path: filePath,
                        isUnderLib: isUnderLib,
                      )
                    : LoadedFile.parsed(
                        parsed: someResult,
                        path: filePath,
                        isUnderLib: isUnderLib,
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
        } finally {
          // Fired for every file, including error/part/continue paths.
          progressSink.advance();
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
      stopResolve?.call();
      progressSink.endPhase();
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

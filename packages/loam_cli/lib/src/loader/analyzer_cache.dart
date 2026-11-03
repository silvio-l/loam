// ignore_for_file: implementation_imports – the analyzer exposes no public way to persist its summary store; this file is the single, deliberate capsule for that internal API (see the analyzer constraint in pubspec.yaml).

import 'dart:io';
import 'dart:math';

import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/src/dart/analysis/file_byte_store.dart';

import 'cache_eviction.dart';

/// The analyzer's summary store kept on disk between runs (issue #8).
///
/// **The only file in loam that touches the analyzer's internal API**
/// (`AnalysisContextCollectionImpl(byteStore:)` and `FileByteStore`). When an
/// analyzer upgrade removes or changes it, this file stops compiling — check
/// it whenever the analyzer constraint in `pubspec.yaml` is raised.
///
/// The store holds linked element summaries of the SDK, the dependencies and
/// the project's own libraries, keyed by the analyzer with its own version and
/// the content signatures it depends on, so a stale entry is never used. A
/// warm store roughly halves the resolve phase.
///
/// Failure model: [open] returns `null` when the directory cannot be created
/// or the store cannot be built, and the caller loads without it. The store
/// itself treats unreadable or corrupt entries (checksum mismatch) as misses
/// and ignores failed writes. Each instance writes with its own temporary
/// file suffix, so parallel runs (even isolates of one process) never write
/// the same temporary file; entries are renamed into place.
final class AnalyzerCache {
  AnalyzerCache._(this.directory, this._store);

  /// Opens (and creates) the store in [directory], or returns `null` when that
  /// fails or [directory] is a symbolic link (the store only ever writes and
  /// deletes inside a real directory of its own) — loam then analyses without
  /// it, as before.
  static AnalyzerCache? open(String directory) {
    try {
      if (FileSystemEntity.isLinkSync(directory)) return null;
      Directory(directory).createSync(recursive: true);
      final suffix = Random().nextInt(1 << 32).toRadixString(16);
      return AnalyzerCache._(
        directory,
        FileByteStore(directory, tempNameSuffix: suffix),
      );
    } on Object {
      return null;
    }
  }

  /// Upper bound for the store on disk. Entries are only added by the
  /// analyzer, never refreshed, so the store grows with every change to the
  /// SDK, dependencies or project; [close] trims it back below this size.
  static const int maxBytes = 512 * 1024 * 1024;

  /// The directory holding the store.
  final String directory;

  final FileByteStore _store;

  /// An [AnalysisContextCollection] backed by this store.
  AnalysisContextCollection collection({
    required List<String> includedPaths,
    required String sdkPath,
  }) => AnalysisContextCollectionImpl(
    includedPaths: includedPaths,
    sdkPath: sdkPath,
    byteStore: _store,
  );

  /// Waits for pending writes, removes temporary files that earlier runs left
  /// behind and trims the store when this run wrote to it.
  /// With [discard], deletes the whole store instead (a load with it failed,
  /// so the next run starts from an empty store rather than failing and
  /// loading twice again). Never throws.
  Future<void> close({bool discard = false}) async {
    try {
      await _store.flush();
      await _waitForPendingWrites();
      if (discard) {
        Directory(directory).deleteSync(recursive: true);
      } else {
        removeOrphanedTempFiles(Directory(directory), now: DateTime.now());
        if (_store.writeCount > 0) {
          evictOldest(Directory(directory), maxBytes: maxBytes);
        }
      }
    } on Object {
      // A failed flush or trim only costs a later cache miss; the run's
      // results are already complete.
      return;
    }
  }

  /// Upper bound for [close] to wait on writes still in flight. A write
  /// always finishes (failures are swallowed by the store), so this only
  /// guards against a stalled file system.
  static const Duration writeWaitLimit = Duration(minutes: 1);

  /// `FileByteStore.flush` returns at once on Windows (dart-lang/sdk#64190),
  /// while its writes still run. Without this wait the trim or discard races
  /// the writes, and a process that exits right after loses them and leaves
  /// `*-temp-*` files behind. Polls the store's own pending counter, which
  /// drops once an entry is renamed into place.
  Future<void> _waitForPendingWrites() async {
    final elapsed = Stopwatch()..start();
    while (_store.pendingWriteCount > 0 && elapsed.elapsed < writeWaitLimit) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }
}

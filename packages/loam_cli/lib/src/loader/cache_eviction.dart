import 'dart:io';

/// Keeps a cache directory below [maxBytes] by deleting its oldest files.
///
/// Does nothing while the directory holds at most [maxBytes]. Above that it
/// deletes files in order of their last access time, least recently used
/// first (the store reads entries without rewriting them, so the access time
/// is what tells a still-used entry from a stale one; on file systems that
/// update it lazily, e.g. Linux `relatime`, the order is approximate), until at
/// most three quarters of [maxBytes] remain, so the next runs do not trim
/// again right away. A deleted entry that is still needed is just a cache
/// miss and gets written again. Files that vanish or cannot be deleted (a
/// parallel run) are skipped. Symbolic links are never followed, so a link
/// planted in the directory (e.g. by a checked-out repository) cannot make it
/// delete files elsewhere. Returns the number of deleted files.
int evictOldest(Directory directory, {required int maxBytes}) {
  final files = <(File, FileStat)>[];
  var total = 0;
  for (final entity in directory.listSync(
    recursive: true,
    followLinks: false,
  )) {
    if (entity is! File) continue;
    final stat = entity.statSync();
    if (stat.type != FileSystemEntityType.file) continue;
    files.add((entity, stat));
    total += stat.size;
  }
  if (total <= maxBytes) return 0;
  files.sort((a, b) => a.$2.accessed.compareTo(b.$2.accessed));
  final target = maxBytes * 3 ~/ 4;
  var deleted = 0;
  for (final (file, stat) in files) {
    if (total <= target) break;
    try {
      file.deleteSync();
    } on FileSystemException {
      continue;
    }
    total -= stat.size;
    deleted++;
  }
  return deleted;
}

/// Deletes temporary store files that no run will finish any more.
///
/// The store writes each entry to `<key>-temp-<pid>…` in [directory] and
/// renames it into its shard. A run that ends while a write is still in
/// flight (the analyzer does not wait for its writes on Windows,
/// dart-lang/sdk#64190) leaves that file behind. Only files modified before
/// [now] minus [maxAge] are removed, so a parallel run's write in progress is
/// never touched. Only the top level is scanned (temporary files never sit in
/// a shard), symbolic links are skipped, and files that vanish or cannot be
/// deleted are skipped. Returns the number of deleted files.
int removeOrphanedTempFiles(
  Directory directory, {
  required DateTime now,
  Duration maxAge = const Duration(hours: 1),
}) {
  final cutoff = now.subtract(maxAge);
  var deleted = 0;
  for (final entity in directory.listSync(followLinks: false)) {
    if (entity is! File || !entity.uri.pathSegments.last.contains('-temp-')) {
      continue;
    }
    try {
      final stat = entity.statSync();
      if (stat.type != FileSystemEntityType.file) continue;
      if (!stat.modified.isBefore(cutoff)) continue;
      entity.deleteSync();
      deleted++;
    } on FileSystemException {
      continue;
    }
  }
  return deleted;
}

import 'dart:io' hide FileLock;
import 'dart:io' as io show FileLock;

/// A cross-process lock with exactly one owner, backed by an exclusive
/// operating-system lock on a lock file (`flock`/`fcntl` on macOS and Linux,
/// `LockFileEx` on Windows).
///
/// The operating system drops the lock when the owning process ends, however
/// it ends, so there is no staleness to detect and no age or PID heuristic: a
/// crashed run never blocks later runs. The file itself is never deleted, so
/// nobody can lock a file that another process has just unlinked.
class FileLock {
  /// Creates a lock on the file at [path].
  FileLock(this.path);

  /// The lock file.
  final String path;

  /// Paths locked by this process. Operating-system locks do not reliably
  /// exclude two handles of the same process, so this covers that case.
  static final Set<String> _heldHere = <String>{};

  RandomAccessFile? _handle;

  /// Tries once to take the lock; `false` when another owner has it.
  bool tryAcquire() {
    if (_handle != null) return false;
    final key = File(path).absolute.path;
    if (_heldHere.contains(key)) return false;
    RandomAccessFile? handle;
    try {
      File(path).parent.createSync(recursive: true);
      handle = File(path).openSync(mode: FileMode.append);
      // [io.FileLock.exclusive] does not wait: it throws while someone else has it.
      handle.lockSync(io.FileLock.exclusive);
    } on FileSystemException {
      handle?.closeSync();
      return false;
    }
    _handle = handle;
    _heldHere.add(key);
    return true;
  }

  /// Releases the lock if this instance holds it. Never throws.
  void release() {
    final handle = _handle;
    _handle = null;
    if (handle == null) return;
    _heldHere.remove(File(path).absolute.path);
    try {
      handle.closeSync(); // Closing also unlocks.
    } on FileSystemException {
      // The process end releases it anyway.
      return;
    }
  }
}

// ignore_for_file: unused_element – fixture declarations are loaded by ProjectLoader only.

// Negative fixture: informative // comments that are not workflow markers.
class _Cache {
  void _refresh() {
    // Skip the network round-trip when the local entry is still fresh.
    _readLocal();
    // Otherwise fall back to the remote source and update the cache.
    _readRemote();
  }

  void _readLocal() {}
  void _readRemote() {}
}

// Negative fixture: /// dartdoc comments → NEVER flagged (Dartdoc-Tabu),
// even when they look like a workflow sequence.
// ignore_for_file: unused_element – fixture declarations are loaded by ProjectLoader only.

class _Pipeline {
  void _run() {
    /// Step 1: read the input
    _read();

    /// Step 2: transform the input
    _transform();
  }

  void _read() {}
  void _transform() {}
}

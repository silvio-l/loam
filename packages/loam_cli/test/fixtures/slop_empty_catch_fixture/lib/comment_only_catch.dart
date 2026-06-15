// Positive fixture: comment-only catch body — expects 1 Finding.
// This is the case that dart's built-in empty_catches lint misses.

/// Example function with a catch body containing only a comment.
void commentOnlyCatchExample() {
  try {
    throw Exception('test');
  } catch (e) {
    // TODO: handle this properly
  }
}

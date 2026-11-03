// Positive fixture: the wildcard only exempts a literally empty body.

/// Wildcard plus a comment-only body — still flagged.
void wildcardWithCommentExample() {
  try {
    throw Exception('test');
  } catch (_) {
    // TODO: decide what to do
  }
}

/// Wildcard exception but a stack trace parameter — still flagged.
void wildcardWithStackTraceExample() {
  try {
    throw Exception('test');
    // ignore: unused_catch_stack — fixture
  } catch (_, st) {}
}

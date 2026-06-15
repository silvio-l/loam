// Negative fixture: rethrow in catch body — expects 0 Findings.

/// Example function that rethrows — must NOT be flagged.
void rethrowCatchExample() {
  try {
    throw Exception('test');
  } catch (e) {
    rethrow;
  }
}

/// Catch with throw (wraps in domain error) — must NOT be flagged.
void throwCatchExample() {
  try {
    throw Exception('test');
  } catch (e) {
    throw StateError('wrapped: $e');
  }
}

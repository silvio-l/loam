// Negative fixture: `catch (_) {}` is the explicit "ignored on purpose" marker.

/// Wildcard catch with an empty body — must NOT be flagged.
void wildcardCatchExample() {
  try {
    throw Exception('test');
  } catch (_) {}
}

/// Typed wildcard catch with an empty body — must NOT be flagged.
void typedWildcardCatchExample() {
  try {
    throw Exception('test');
  } on FormatException catch (_) {}
}

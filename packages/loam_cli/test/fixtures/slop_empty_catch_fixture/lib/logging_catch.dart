// Negative fixture: logging call in catch body — expects 0 Findings.
// ignore: avoid_print — fixture file; print stands in for a real logger call in this test fixture

/// Example function with a logging call (print) — must NOT be flagged.
void printLoggingCatchExample() {
  try {
    throw Exception('test');
  } catch (e) {
    // ignore: avoid_print — test fixture; print is intentionally used as a logging-call stand-in
    print('error: $e');
  }
}

/// Example function with a log() call — must NOT be flagged.
void logCatchExample() {
  try {
    throw Exception('test');
  } catch (e) {
    log('error', error: e);
  }
}

/// Stub log function used by the fixture — not a real implementation.
void log(String message, {Object? error}) {}

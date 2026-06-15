// Negative fixture: // ignore: with comment on line above — expects 0 Findings.

/// Example function with a justified // ignore: (reason on line above).
void justifiedLineAboveExample() {
  // This specific print is part of the CLI output, not a debug statement.
  // ignore: avoid_print
  print('hello');
}

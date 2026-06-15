// Positive fixture: empty catch body — expects 1 Finding on the catch clause.

/// Example function with a literally empty catch body.
void emptyCatchExample() {
  try {
    throw Exception('test');
  } catch (
    e
  ) {} // ignore: empty_catches — dart lint suppressed; loam slop-empty-catch still fires on AST
}

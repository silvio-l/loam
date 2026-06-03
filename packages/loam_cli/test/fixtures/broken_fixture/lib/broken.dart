/// This file intentionally contains a semantic error to test the error path.
///
/// The file is syntactically valid (dart format can parse it) but has a
/// type error that the analyzer reports as Severity.error.
void brokenFunction() {
  // Assigning int to String is a type error (invalid_assignment).
  // NOLINTNEXTLINE — intentional error for fixture purposes
  String value = 42; // error: int can't be assigned to String
  print(value);
}

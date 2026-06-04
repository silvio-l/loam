/// A public class that is never referenced anywhere in the project.
/// Should be reported as unused.
class UnusedClass {
  String get name => 'unused';
}

/// Another unused public class — one finding per symbol expected.
class AnotherUnusedClass {
  int get value => 42;
}

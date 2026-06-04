/// A public class that IS referenced from another lib file.
/// Should NOT be reported as unused.
class UsedClass {
  String get name => 'used';
}

/// A private class — never a candidate, regardless of usage.
class _PrivateClass {
  String get name => 'private';
}

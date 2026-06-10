part of 'calculator.dart';

/// A helper class declared in the part file.
/// Symbols here must appear exactly ONCE in the collector's output (no
/// double-counting due to the part/library fragment relationship).
class PartHelper {
  /// Simple method in the part file.
  /// Expected: cyclomatic=1, cognitive=0.
  String greet(String name) => 'Hello, $name!';

  /// Method with a branch in the part file.
  /// Expected: cyclomatic=2, cognitive=1.
  String greetOrFallback(String? name) {
    if (name != null) {
      return 'Hello, $name!';
    }
    return 'Hello, stranger!';
  }
}

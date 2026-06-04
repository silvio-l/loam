/// Library file covering every public top-level declaration kind for the
/// unused-public-exports fixture (Issue 02).
///
/// Contains:
///   - Used and unused top-level functions
///   - Used and unused top-level getters/setters
///   - Used and unused enums
///   - Used and unused extensions
///   - Used and unused mixins
///   - Used and unused typedefs
///   - Used and unused top-level variables
library;

part 'all_kinds_part.dart';

// ---------------------------------------------------------------------------
// Functions
// ---------------------------------------------------------------------------

/// A public function referenced from kinds_consumer.dart — NOT reported.
String usedFunction() => 'used';

/// A public function never referenced anywhere — REPORTED as unused.
String unusedFunction() => 'unused';

// ---------------------------------------------------------------------------
// Getters / setters
// ---------------------------------------------------------------------------

/// A public getter referenced from kinds_consumer.dart — NOT reported.
int get usedGetter => 42;

/// A public getter never referenced anywhere — REPORTED as unused.
int get unusedGetter => 0;

/// A public setter referenced from kinds_consumer.dart — NOT reported.
// ignore: avoid_setters_without_getters
set usedSetter(int _value) {}

/// A public setter never referenced anywhere — REPORTED as unused.
// ignore: avoid_setters_without_getters
set unusedSetter(int _value) {}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// An enum referenced from kinds_consumer.dart — NOT reported.
enum UsedEnum { alpha, beta }

/// An enum never referenced anywhere — REPORTED as unused.
enum UnusedEnum { x, y }

// ---------------------------------------------------------------------------
// Extensions
// ---------------------------------------------------------------------------

/// An extension referenced from kinds_consumer.dart — NOT reported.
extension UsedExtension on String {
  String get exclaimed => '$this!';
}

/// An extension never referenced anywhere — REPORTED as unused.
extension UnusedExtension on int {
  int get doubled => this * 2;
}

// ---------------------------------------------------------------------------
// Mixins
// ---------------------------------------------------------------------------

/// A mixin referenced from kinds_consumer.dart — NOT reported.
mixin UsedMixin {
  String mixinMethod() => 'mixed';
}

/// A mixin never referenced anywhere — REPORTED as unused.
mixin UnusedMixin {
  String otherMethod() => 'unmixed';
}

// ---------------------------------------------------------------------------
// Typedefs
// ---------------------------------------------------------------------------

/// A typedef referenced from kinds_consumer.dart — NOT reported.
typedef UsedTypedef = String Function(int);

/// A typedef never referenced anywhere — REPORTED as unused.
typedef UnusedTypedef = int Function(String);

// ---------------------------------------------------------------------------
// Top-level variables
// ---------------------------------------------------------------------------

/// A top-level variable referenced from kinds_consumer.dart — NOT reported.
const String usedVariable = 'used_variable';

/// A top-level variable never referenced anywhere — REPORTED as unused.
const String unusedVariable = 'unused_variable';

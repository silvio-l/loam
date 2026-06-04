/// Fixture library for Slice B (member support) tests.
///
/// Covers:
///   - Unused vs used public methods
///   - Unused vs used public fields
///   - Unused vs used public getter/setter members
///   - @override member (must NOT be reported)
///   - Interface-implementing member (must NOT be reported)
///   - Synthetic enum members (values/index, must NOT be reported)
///   - Enum constant fields (must NOT be reported)
library;

// ---------------------------------------------------------------------------
// Abstract interface defining a member contract
// ---------------------------------------------------------------------------

/// Abstract interface used to test that implementing members are excluded.
abstract class MemberInterface {
  String interfaceMethod();
  String get interfaceGetter;
}

// ---------------------------------------------------------------------------
// Class with used and unused public members
// ---------------------------------------------------------------------------

/// A class with a mix of used and unused public members.
class MemberHost implements MemberInterface {
  /// A public method that IS referenced from members_consumer.dart — NOT reported.
  String usedMethod() => 'used';

  /// A public method NEVER referenced anywhere — REPORTED.
  String unusedMethod() => 'unused';

  /// A public field that IS referenced from members_consumer.dart — NOT reported.
  String usedField = 'used_field';

  /// A public field NEVER referenced anywhere — REPORTED.
  String unusedField = 'unused_field';

  /// A public getter that IS referenced from members_consumer.dart — NOT reported.
  int get usedMemberGetter => 1;

  /// A public getter NEVER referenced anywhere — REPORTED.
  int get unusedMemberGetter => 0;

  /// A public setter that IS referenced from members_consumer.dart — NOT reported.
  // ignore: avoid_setters_without_getters
  set usedMemberSetter(int _v) {}

  /// A public setter NEVER referenced anywhere — REPORTED.
  // ignore: avoid_setters_without_getters
  set unusedMemberSetter(int _v) {}

  /// Implements [MemberInterface.interfaceMethod] — must NOT be reported.
  @override
  String interfaceMethod() => 'impl';

  /// Implements [MemberInterface.interfaceGetter] — must NOT be reported.
  @override
  String get interfaceGetter => 'getter_impl';
}

// ---------------------------------------------------------------------------
// Class with only @override members (Object methods)
// ---------------------------------------------------------------------------

/// A class that overrides Object.toString() — must NOT be reported.
class HasOverrideMethod {
  final String value;
  const HasOverrideMethod(this.value);

  @override
  String toString() => 'HasOverrideMethod($value)';
}

// ---------------------------------------------------------------------------
// Enum — synthetic members must NOT be reported
// ---------------------------------------------------------------------------

/// Enum to test that values/index (synthetic fields) are never reported.
enum MemberEnum {
  alpha,
  beta;

  /// A public method on the enum that IS referenced — NOT reported.
  String usedEnumMethod() => name.toUpperCase();

  /// A public method on the enum NEVER referenced anywhere — REPORTED.
  String unusedEnumMethod() => name.toLowerCase();
}

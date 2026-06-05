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

// ---------------------------------------------------------------------------
// Member-name collision (regression guard, derived from a real HellerIO case).
//
// Two unrelated classes each declare a public method with the SAME unqualified
// name `fatal`. Only `SdkStyleLogger.fatal` is ever called; `AppLoggerLike.fatal`
// has zero callers. A correct, *semantic* (element-model) usage resolution must
// report `AppLoggerLike.fatal` while leaving `SdkStyleLogger.fatal` untouched.
//
// A naive *name-based* implementation would see the `.fatal(` call on the SDK
// logger and wrongly mark ALL methods named `fatal` as used — suppressing the
// genuine finding (a false negative). This is exactly the trap that fooled a
// careful grep-based reviewer on HellerIO's `AppLogger.fatal` vs `Sentry.logger.fatal`.
// ---------------------------------------------------------------------------

/// Mirrors HellerIO's hand-written `AppLogger`: the class itself is used, but
/// its `fatal` member is never called — `fatal` MUST be reported.
class AppLoggerLike {
  /// A public method that IS referenced from members_consumer.dart — keeps the
  /// class "used" so member-level analysis applies. NOT reported.
  String note(Object? message) => 'note: $message';

  /// Same unqualified name as `SdkStyleLogger.fatal` but never called — REPORTED.
  /// (Plain backticks, not a doc reference, so this comment is not a usage.)
  void fatal(Object? message, [Object? error, StackTrace? stackTrace]) {}
}

/// Mirrors HellerIO's external structured logger (e.g. `Sentry.logger`): a
/// different type that happens to expose a `fatal` method which IS called —
/// `fatal` MUST NOT be reported.
class SdkStyleLogger {
  /// Same unqualified name as `AppLoggerLike.fatal` but IS called from
  /// members_consumer.dart — NOT reported.
  Future<void> fatal(
    Object? message, {
    Map<String, Object?>? attributes,
  }) async {}
}

// ---------------------------------------------------------------------------
// Static field access regression (derived from HellerIO FP #2).
//
// A static field accessed via ClassName.fieldName must NOT be reported as
// unused. This exercises the HellerIO pattern where a static Map accessed as
// `SystemIds.systemCategoryIdByL10nKey` in another file was incorrectly
// reported as unused because _collectMemberIds did not handle FieldDeclaration
// (only VariableDeclaration) — leaving the field id absent from declaredIds and
// causing the declaration-site visit to self-register as a reference.
// ---------------------------------------------------------------------------

/// Class with static fields accessed via ClassName.field.
///
/// Reproduces HellerIO FP #2: a static field accessed only as
/// `StaticFieldHolder.usedStaticField` or via index access
/// `StaticFieldHolder.usedStaticMap['key']` must NOT be reported.
abstract final class StaticFieldHolder {
  /// A static field that IS referenced externally — NOT reported.
  static const String usedStaticField = 'used';

  /// A static Map field accessed via index — NOT reported.
  static const Map<String, String> usedStaticMap = {'key': 'value'};

  /// A static field that is NOT referenced anywhere — REPORTED.
  static const String unusedStaticField = 'unused';

  /// A static Map field that is NOT referenced anywhere — REPORTED.
  static const Map<String, String> unusedStaticMap = {'k': 'v'};

  /// A static method that IS called via ClassName.method() — NOT reported.
  static String usedStaticMethod() => 'used';

  /// A static method that is NOT referenced anywhere — REPORTED.
  static String unusedStaticMethod() => 'unused';

  /// A static getter that IS read via ClassName.getter — NOT reported.
  static int get usedStaticGetter => 0;

  /// A static getter that is NOT referenced anywhere — REPORTED.
  static int get unusedStaticGetter => 1;
}

// ---------------------------------------------------------------------------
// Setter-only-used static getter/setter PAIR (derived from HellerIO
// AppMonitoring.crashReportingConsent).
//
// An explicit static getter+setter pair shares one logical symbol. The setter
// IS assigned from members_consumer.dart (`StaticConsent.granted = true`); the
// getter is NEVER read. Because the usage index canonicalises getter and setter
// to the same backing variable, touching the symbol via the setter must count
// as a reference — the pair must NOT be reported as unused. A gap in
// setter-assignment resolution would falsely report `granted` (HellerIO
// `crashReportingConsent` case).
// ---------------------------------------------------------------------------

/// Static get/set pair whose setter IS used but whose getter is never read.
abstract final class StaticConsent {
  static bool _granted = false;

  /// Getter is never read anywhere — but the paired setter IS assigned, so the
  /// shared symbol must NOT be reported.
  static bool get granted => _granted;

  /// Setter assigned from members_consumer.dart via `StaticConsent.granted = …`.
  static set granted(bool value) => _granted = value;
}

// ---------------------------------------------------------------------------
// Write-only PLAIN field (FN regression guard for the setter-write fix).
//
// `writeOnlyField` is assigned from members_consumer.dart but never read.
// A write to a plain field resolves to a *synthetic* field-induced setter; the
// setter-write fix must NOT count that as usage, otherwise genuinely dead
// write-only fields (the exact "AI slop" the rule exists to surface — HellerIO
// stripped SyncStateSuccess.at/.pushed etc. for being write-only) would be
// masked. This field MUST stay reported as unused.
// ---------------------------------------------------------------------------

/// A class with a public field that is only ever assigned, never read.
class WriteOnlyHolder {
  /// Assigned via `holder.writeOnlyField = …`, never read — MUST be reported.
  String writeOnlyField = '';
}

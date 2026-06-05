/// Fixture: a library with a static field that is ONLY referenced from a part
/// file of ANOTHER library.
///
/// Reproduces HellerIO FP #2: the UsageIndex must scan part-file compilation
/// units, otherwise references to `PartRefProvider.usedViaPartFile` are
/// invisible (the part file is not a standalone resolved entry) and the field
/// is incorrectly reported as unused.
library;

abstract final class PartRefProvider {
  /// A static field that IS referenced, but ONLY from a part file (lib/part_ref_impl.dart).
  /// Must NOT be reported as unused.
  static const String usedViaPartFile = 'referenced_from_part';

  /// A static field that is NOT referenced anywhere.
  /// Must be reported as unused.
  static const String unusedViaPartFile = 'not_referenced';
}

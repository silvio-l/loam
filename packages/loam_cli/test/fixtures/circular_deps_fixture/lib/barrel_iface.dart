/// Barrel interface — the idiomatic Flutter platform-split / re-export pattern.
///
/// `barrel_iface.dart` defines the public abstraction and **re-exports** its
/// implementation (`barrel_impl.dart`), while the implementation **imports**
/// this file to implement the abstraction. The loop is closed only by the
/// `export` directive — a re-export, not a functional dependency.
///
/// This must NOT be reported as a circular dependency: it mirrors the real
/// WhisPaste `paster.dart` ↔ `desktop_paster.dart` pattern (interface library
/// re-exports its concrete impl). Counting export edges would make this a false
/// positive on intentional, recommended Dart code.
library;

export 'package:circular_deps_fixture/barrel_impl.dart';

/// The public abstraction consumers implement.
abstract class BarrelIface {
  /// A capability the implementation provides.
  String describe();
}

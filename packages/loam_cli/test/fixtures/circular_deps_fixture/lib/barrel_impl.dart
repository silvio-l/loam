/// Barrel implementation — imports the interface it implements.
///
/// `barrel_impl.dart` IMPORTS `barrel_iface.dart` (a real functional
/// dependency: it needs the `BarrelIface` type to implement it). The interface
/// re-EXPORTS this file back. The only cycle-closing edge is that export, so
/// under an import-only dependency graph there is no cycle here — exactly the
/// intended behaviour (no false positive on the platform-split idiom).
library;

import 'package:circular_deps_fixture/barrel_iface.dart';

/// Concrete implementation of [BarrelIface].
class BarrelImpl implements BarrelIface {
  @override
  String describe() => 'barrel impl';
}

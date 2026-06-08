/// Zeta — re-exports eta (creates an export edge zeta→eta).
///
/// Together with eta re-exporting zeta, this forms an export cycle: zeta↔eta.
library;

export 'package:circular_deps_fixture/eta.dart';

/// A class in zeta.
class Zeta {}

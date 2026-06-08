/// Eta — re-exports zeta (creates an export edge eta→zeta, completing an export cycle).
///
/// Together with zeta re-exporting eta, this forms an export cycle: eta↔zeta.
library;

export 'package:circular_deps_fixture/zeta.dart';

/// A class in eta.
class Eta {}

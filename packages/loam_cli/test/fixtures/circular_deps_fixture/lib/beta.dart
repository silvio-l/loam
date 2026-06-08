/// Beta — imports alpha back (creates the return edge beta→alpha, completing a cycle).
library;

import 'package:circular_deps_fixture/alpha.dart';

/// A class that uses Alpha.
class Beta {
  /// Returns an Alpha instance.
  Alpha makeAlpha() => Alpha();
}

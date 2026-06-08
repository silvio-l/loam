/// Alpha — imports beta (creates a forward edge alpha→beta).
library;

import 'package:circular_deps_fixture/beta.dart';

/// A class that uses Beta.
class Alpha {
  /// Returns a Beta instance.
  Beta makeBeta() => Beta();
}

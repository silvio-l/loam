/// ExternalUser — imports only dart:core and external packages.
///
/// These imports must NOT create edges or nodes in the ImportGraph.
library;

import 'dart:math';

/// A class that uses only dart: imports.
class ExternalUser {
  /// Returns a random double.
  double randomValue() => Random().nextDouble();
}

/// RelativeImporter — imports delta using a relative path (not package: URI).
///
/// Relative imports to first-party lib/ files must also create graph edges.
library;

import 'delta.dart';

/// A class that uses Delta via relative import.
class RelativeImporter {
  /// Returns a Delta instance.
  Delta makeDelta() => Delta();
}

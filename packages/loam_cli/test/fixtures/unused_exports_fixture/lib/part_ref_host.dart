/// Fixture: a library file that includes a part file (part_ref_impl.dart).
///
/// The part file contains a reference to PartRefProvider.usedViaPartFile.
/// Because part files are skipped as standalone entries by ProjectLoader (they
/// are not libraries), UsageIndex must still visit their compilation units to
/// detect the reference — otherwise symbols referenced only from part files are
/// incorrectly reported as unused.
library;

import 'package:unused_exports_fixture/part_ref_provider.dart';

part 'part_ref_impl.dart';

/// A class that exists so this library file is meaningful.
class PartRefHost {
  /// Returns the value via the part-file helper.
  String getValue() => PartRefImpl.getRef();
}

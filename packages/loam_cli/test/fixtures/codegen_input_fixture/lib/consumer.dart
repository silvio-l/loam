/// Consumer file that references some symbols to test that UsageIndex is
/// unaffected by the codegen classifier.
///
/// A symbol used only from a code-gen input class must still count as "used"
/// because the UsageIndex is not affected by the classifier (Invariant 4).
library;

import 'plain_class.dart';

/// A helper class that is only referenced from [DriftTableConsumer] below.
/// This tests that references FROM code-gen input classes still count as usage.
class HelperUsedOnlyFromDriftTable {
  const HelperUsedOnlyFromDriftTable();
}

/// Simulates a code-gen input class that internally uses [HelperUsedOnlyFromDriftTable].
/// Even though this class's members would be excluded (if it were a Drift class),
/// its *references* must still count in the UsageIndex.
class DriftTableConsumer {
  // Using HelperUsedOnlyFromDriftTable as a field — this is a reference.
  final HelperUsedOnlyFromDriftTable helper;
  // Using PlainClass as a field — ensures PlainClass is not flagged as unused.
  final PlainClass? plainRef;
  const DriftTableConsumer(this.helper, {this.plainRef});
}

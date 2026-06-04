/// A class declared in a regular lib/ file that is ONLY referenced from a
/// *.g.dart file (generated_lib.g.dart).
///
/// Must NOT be reported as unused because references from generated files
/// still count as usage in UsageIndex.
class UsedOnlyFromGenerated {
  String get name => 'used_only_from_generated';
}

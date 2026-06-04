part of 'all_kinds.dart';

/// A class declared in a part file and referenced from kinds_consumer.dart.
/// Must NOT be reported (used) and must NOT be double-reported (part dedup).
class UsedPartClass {
  String get name => 'used_part';
}

/// A class declared in a part file, never referenced anywhere.
/// Must be reported EXACTLY ONCE.
class UnusedPartClass {
  String get name => 'unused_part';
}

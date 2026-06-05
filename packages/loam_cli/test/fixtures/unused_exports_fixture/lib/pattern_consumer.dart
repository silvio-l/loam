import 'package:unused_exports_fixture/pattern_match.dart';

/// Consumer that reads the `patternRead` field of [PatternHost] ONLY through
/// object-pattern destructuring — never via a member access. Deliberately NO
/// square-bracket doc reference to the field itself, so the object pattern is
/// the sole usage signal (a `[PatternHost.patternRead]` reference would mask the
/// bug, as a CommentReference resolves to the field element).
String describe(Object value) {
  return switch (value) {
    PatternHost(:final patternRead) => patternRead,
    _ => 'other',
  };
}

/// Fixture for members the Dart runtime invokes without a static call site.
library;

/// Serialised through `jsonEncode`, which calls `toJson` dynamically.
class DynamicHost {
  /// Called by `jsonEncode` — must NOT be reported although it has no
  /// `@override` and no static call site.
  Map<String, dynamic> toJson() => {'k': 1};

  /// Invoked as `host()` on a dynamic value — must NOT be reported.
  int call() => 1;

  /// Plain member without any caller — the control, REPORTED.
  int unusedDynamicControl() => 2;
}

// Negative fixture: legitimate uses of the same constructs.

/// Stand-in for package:plugin_platform_interface.
class PlatformInterface {}

/// Flutter plugin template: default that platform packages override.
class PluginPlatform extends PlatformInterface {
  /// Template default.
  String version() => throw UnimplementedError();
}

/// Template method: subclasses must override.
abstract class Base {
  /// Template.
  void run() => throw UnimplementedError();
}

/// Sealed template.
sealed class Shape {
  /// Template.
  double area() => throw UnimplementedError();
}

/// Mixin template.
mixin Template {
  /// Template.
  void hook() => throw UnimplementedError();
}

/// Not the stub: other statements, other errors, other types.
class Real {
  /// Unsupported value in a default branch.
  int pick(int v) {
    switch (v) {
      case 1:
        return 1;
      default:
        throw UnimplementedError();
    }
  }

  /// Deliberate, documented failure.
  void other() => throw UnsupportedError('read-only');

  /// Logs first, so it is not only a stub.
  void both() {
    pick(1);
    throw UnimplementedError();
  }

  /// Different type with the same name.
  void shadow() => throw _Local();
}

class _Local extends Error {}

/// Mixin class template.
mixin class MixinTemplate {
  /// Template.
  void hook() => throw UnimplementedError();
}

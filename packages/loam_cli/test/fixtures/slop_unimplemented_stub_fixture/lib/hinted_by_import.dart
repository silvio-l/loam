import 'foo_platform_interface.dart';
import 'unknown.dart';

/// Base class name carries no hint, but the file imports a platform interface.
class Impl extends Unknown {
  /// Keeps the platform-interface import in use.
  FooPlatform? platform;

  /// Template default.
  String other() => throw UnimplementedError();
}

import 'legit.dart';

/// Plugin platform interface living in its own file.
abstract class FooPlatform extends PlatformInterface {
  /// Template default.
  String version() => throw UnimplementedError();
}

/// Intermediate link of the chain, not abstract.
class BaseFoo extends FooPlatform {
  /// Template default.
  String name() => throw UnimplementedError();
}

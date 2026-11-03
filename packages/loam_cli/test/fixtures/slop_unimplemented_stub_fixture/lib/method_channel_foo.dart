import 'foo_platform_interface.dart';

/// Chain crosses a file boundary: the base class is declared elsewhere.
class MethodChannelFoo extends BaseFoo {
  /// Template default.
  String other() => throw UnimplementedError();
}

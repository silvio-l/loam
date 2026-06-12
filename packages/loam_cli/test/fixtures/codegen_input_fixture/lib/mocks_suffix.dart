/// Library with a generated `*.mocks.dart` part directive (mockito pattern).
///
/// Used to verify that the structural fallback recognises `*.mocks.dart` as a
/// generated suffix — analogous to the existing `*.g.dart` check.
library;

part 'mocks_suffix.mocks.dart';

/// mockito-style test helper that binds its generated counterpart `_$…`.
/// Its public members are consumed by the generator → code-gen input (fallback).
class MocksSuffixLib extends _$MocksSuffixLib {
  /// A public method — classified as code-gen input via the narrowed fallback.
  void verify() {}
}

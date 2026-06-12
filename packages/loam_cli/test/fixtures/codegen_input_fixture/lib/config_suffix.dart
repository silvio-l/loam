/// Library with a generated `*.config.dart` part directive (injectable pattern).
///
/// Used to verify that the structural fallback recognises `*.config.dart` as a
/// generated suffix — analogous to the existing `*.g.dart` check.
library;

part 'config_suffix.config.dart';

/// injectable-style module that binds its generated counterpart `_$…`.
/// Its public members are consumed by the generator → code-gen input (fallback).
class ConfigSuffixModule extends _$ConfigSuffixModule {
  /// A public getter — classified as code-gen input via the narrowed fallback.
  String get apiUrl => 'https://api.example.com';
}

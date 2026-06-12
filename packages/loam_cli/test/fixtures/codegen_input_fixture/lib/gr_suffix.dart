/// Library with a generated `*.gr.dart` part directive (auto_route pattern).
///
/// Used to verify that the structural fallback recognises `*.gr.dart` as a
/// generated suffix — analogous to the existing `*.g.dart` check.
library;

part 'gr_suffix.gr.dart';

/// auto_route-style router class that binds its generated counterpart `_$…`.
/// Its public members are consumed by the generator → code-gen input (fallback).
class GrSuffixRouter extends _$GrSuffixRouter {
  /// A public method — classified as code-gen input via the narrowed fallback.
  List<Object> get routes => const [];
}

/// Library with a generated `*.pb.dart` part directive (protobuf pattern).
///
/// Used to verify that the structural fallback recognises `*.pb.dart` as a
/// generated suffix — analogous to the existing `*.g.dart` check.
library;

part 'pb_suffix.pb.dart';

/// protobuf-style message that binds its generated counterpart `_$…`.
/// Its public members are consumed by the generator → code-gen input (fallback).
class PbSuffixMessage extends _$PbSuffixMessage {
  /// A public field — classified as code-gen input via the narrowed fallback.
  final String payload;
  PbSuffixMessage(this.payload);
}

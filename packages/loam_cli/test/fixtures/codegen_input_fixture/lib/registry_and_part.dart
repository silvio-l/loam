/// Fixture: class that carries BOTH a registry annotation AND lives in a
/// library with a generated part directive.
///
/// Used to verify the classification order guarantee:
///   registry path (annotation or base-type) MUST win over the structural
///   fallback — reason must start with 'annotation:' or 'base_type:', never
///   'fallback:part_generated'.
library;

import 'annotation_stubs.dart';

part 'registry_and_part.g.dart';

/// A class that carries @JsonSerializable (annotation registry path)
/// AND whose library declares part 'registry_and_part.g.dart'.
///
/// Expected classification: annotation:JsonSerializable (NOT fallback).
@JsonSerializable()
class RegistryAndPartClass {
  /// Public field — must NOT be reported (class is a code-gen input).
  final String label;
  const RegistryAndPartClass(this.label);
}

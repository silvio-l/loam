/// Fixture classes with code-gen annotations.
///
/// Each class carries one of the annotations that the CodegenInputClassifier
/// recognises via its annotation registry. These classes are used to verify
/// that the annotation-registry path in the classifier works correctly.
library;

import 'annotation_stubs.dart';

/// @DriftDatabase — marks a class as a Drift database definition.
/// Its public members are consumed by the Drift code generator.
@DriftDatabase()
class AnnotatedDriftDatabase {
  /// A public member on a @DriftDatabase class — must NOT be reported.
  String get version => '1.0';
}

/// @DataClassName — marks a Drift companion / data class.
/// Its public members are consumed by the Drift code generator.
@DataClassName('MyData')
class AnnotatedDataClassName {
  /// A public member on a @DataClassName class — must NOT be reported.
  final String value;
  const AnnotatedDataClassName(this.value);
}

/// @Riverpod (class form) — marks a Riverpod provider.
/// Its public members are consumed by the Riverpod code generator.
@Riverpod()
class AnnotatedRiverpodClass {
  /// A public method on a @Riverpod class — must NOT be reported.
  String build() => 'result';
}

/// @riverpod (constant form) — marks a Riverpod provider.
/// Its public members are consumed by the Riverpod code generator.
@riverpod
class AnnotatedRiverpodConst {
  /// A public method on a @riverpod class — must NOT be reported.
  String build() => 'result';
}

/// @freezed — marks a freezed value class.
/// Its public members are consumed by the freezed code generator.
@freezed
class AnnotatedFreezed {
  /// A public field on a @freezed class — must NOT be reported.
  final String name;
  const AnnotatedFreezed(this.name);
}

/// @JsonSerializable — marks a class as JSON-serializable.
/// Its public members are consumed by json_serializable's code generator.
@JsonSerializable()
class AnnotatedJsonSerializable {
  /// A public field on a @JsonSerializable class — must NOT be reported.
  final String id;
  const AnnotatedJsonSerializable(this.id);
}

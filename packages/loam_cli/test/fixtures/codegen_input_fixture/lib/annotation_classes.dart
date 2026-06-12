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

/// @injectable (constant form) — marks a class for dependency injection.
/// Its public members are consumed by the injectable code generator.
@injectable
class AnnotatedInjectable {
  /// A public field on an @injectable class — must NOT be reported.
  final String serviceId;
  const AnnotatedInjectable(this.serviceId);
}

/// @module (constant form) — marks a module for injectable / get_it.
/// Its public members are consumed by the injectable code generator.
@module
abstract class AnnotatedModule {
  /// A public getter on an @module class — must NOT be reported.
  String get baseUrl => 'https://example.com';
}

/// @RoutePage — marks a widget class as a navigable route (auto_route).
/// Its public members are consumed by the auto_route code generator.
@RoutePage()
class AnnotatedRoutePage {
  /// A public field on a @RoutePage class — must NOT be reported.
  final String title;
  const AnnotatedRoutePage(this.title);
}

/// @GenerateMocks — instructs mockito to generate mock classes.
/// Its public members are consumed by the mockito code generator.
@GenerateMocks([String])
class AnnotatedGenerateMocks {
  /// A public field on a @GenerateMocks class — must NOT be reported.
  final String target;
  const AnnotatedGenerateMocks(this.target);
}

/// @Collection — marks a class as an Isar database collection.
/// Its public members are consumed by the Isar code generator.
@Collection()
class AnnotatedCollection {
  /// A public field on a @Collection class — must NOT be reported.
  final int id;
  const AnnotatedCollection(this.id);
}

/// @Entity — marks a class as an ObjectBox/floor entity.
/// Its public members are consumed by the ObjectBox/floor code generator.
@Entity()
class AnnotatedEntity {
  /// A public field on an @Entity class — must NOT be reported.
  final int id;
  const AnnotatedEntity(this.id);
}

/// @HiveType — marks a class as a Hive type adapter target.
/// Its public members are consumed by the Hive code generator.
@HiveType(typeId: 42)
class AnnotatedHiveType {
  /// A public field on a @HiveType class — must NOT be reported.
  final String label;
  const AnnotatedHiveType(this.label);
}

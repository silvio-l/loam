/// Stub annotation definitions that mimic code-gen annotation types.
///
/// In production code, these would come from their respective packages
/// (drift, riverpod, freezed, json_annotation). Here they are defined locally
/// so the fixture loads without external dependencies.
///
/// The classifier checks unqualified annotation class names via the element
/// model — the stubs only need to have the right names and be valid const
/// constructors to serve as annotations in tests. Fields are intentionally
/// absent to avoid fixture false-positives in the unused-public-exports rule
/// (the annotation classes themselves are not code-gen inputs).
library;

/// Stub for Drift's `@DriftDatabase` annotation.
/// Real: `package:drift/drift.dart`
class DriftDatabase {
  const DriftDatabase();
}

/// Stub for Drift's `@DataClassName` annotation.
/// Real: `package:drift/drift.dart`
class DataClassName {
  // ignore: avoid_unused_constructor_parameters
  const DataClassName(String name);
}

/// Stub for Riverpod's `@Riverpod` annotation (class form).
/// Real: `package:riverpod_annotation/riverpod_annotation.dart`
class Riverpod {
  // ignore: avoid_unused_constructor_parameters
  const Riverpod({bool keepAlive = false});
}

/// Stub for Riverpod's `@riverpod` annotation (constant form).
/// Real: `package:riverpod_annotation/riverpod_annotation.dart`
const riverpod = _Riverpod();

class _Riverpod {
  const _Riverpod();
}

/// Stub for freezed's `@freezed` annotation.
/// Real: `package:freezed_annotation/freezed_annotation.dart`
const freezed = _Freezed();

class _Freezed {
  const _Freezed();
}

/// Stub for json_serializable's `@JsonSerializable` annotation.
/// Real: `package:json_annotation/json_annotation.dart`
class JsonSerializable {
  const JsonSerializable();
}

/// Stub for injectable's `@injectable` annotation (constant form).
/// Real: `package:injectable/injectable.dart`
const injectable = _Injectable();

class _Injectable {
  const _Injectable();
}

/// Stub for injectable's `@module` annotation (constant form).
/// Real: `package:injectable/injectable.dart`
const module = _Module();

class _Module {
  const _Module();
}

/// Stub for auto_route's `@RoutePage` annotation.
/// Real: `package:auto_route/auto_route.dart`
class RoutePage {
  const RoutePage();
}

/// Stub for mockito's `@GenerateMocks` annotation.
/// Real: `package:mockito/annotations.dart`
class GenerateMocks {
  // ignore: avoid_unused_constructor_parameters
  const GenerateMocks(List<Type> classes);
}

/// Stub for Isar's `@Collection` annotation.
/// Real: `package:isar/isar.dart`
class Collection {
  const Collection();
}

/// Stub for ObjectBox/floor `@Entity` annotation.
/// Real: `package:objectbox/objectbox.dart` / `package:floor/floor.dart`
class Entity {
  const Entity();
}

/// Stub for Hive's `@HiveType` annotation.
/// Real: `package:hive/hive.dart`
class HiveType {
  // ignore: avoid_unused_constructor_parameters
  const HiveType({required int typeId});
}

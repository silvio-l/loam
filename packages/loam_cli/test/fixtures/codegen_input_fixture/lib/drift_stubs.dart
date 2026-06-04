/// Stub definitions that mimic Drift's base types for fixture testing.
///
/// In production code, these would be imported from the `drift` package.
/// In fixture tests we define them locally so the fixture loads without
/// external dependencies.
library;

/// Stub for Drift's `Table` base class.
/// Real: `package:drift/drift.dart` → `abstract class Table { … }`
abstract class Table {}

/// Stub for Drift's `DataClass` base class.
/// Real: generated via `@DataClassName` and build_runner.
abstract class DataClass {}

/// Stub for Drift's `View` base class.
/// Real: `package:drift/drift.dart` → `abstract class View { … }`
abstract class View {}

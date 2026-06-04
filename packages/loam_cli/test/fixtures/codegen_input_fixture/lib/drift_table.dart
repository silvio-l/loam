/// Drift-style table class: extends Table and declares column getters.
///
/// In a real Drift project:
///   class Categories extends Table {
///     TextColumn get name => text()();
///     IntColumn get color => integer()();
///   }
///
/// The build_runner reads these getters at build time and generates a
/// companion `categories.g.dart` file — the getters are never statically
/// referenced in the generated code. This is the primary false-positive pattern.
library;

import 'drift_stubs.dart';

/// A Drift-style table class — its public column getters are code-gen inputs
/// consumed by build_runner. They should NOT be reported as unused.
class DriftTable extends Table {
  /// A column getter that is consumed by the Drift code generator — NOT unused.
  String get name => '';

  /// A column getter that is consumed by the Drift code generator — NOT unused.
  int get color => 0;

  /// Another column getter that is consumed by the Drift code generator.
  bool get isDeleted => false;
}

/// A Drift-style DataClass subclass — its public members should be excluded.
class DriftDataClass extends DataClass {
  final String title;
  // ignore: avoid_field_initializers_in_const_classes
  DriftDataClass(this.title);

  /// A public getter on a DataClass — should NOT be reported as unused.
  String get displayTitle => title.toUpperCase();
}

/// A Drift-style View subclass — its public members should be excluded.
class DriftView extends View {
  /// A column getter on a View — should NOT be reported as unused.
  String get summary => '';
}

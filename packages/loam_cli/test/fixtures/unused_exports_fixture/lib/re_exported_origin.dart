/// A class that is re-exported via a barrel file (re_export_barrel.dart).
///
/// Must NOT be reported as unused because it is part of the public API
/// via re-export — even if no file inside the project directly imports it.
class ReExportedClass {
  String get name => 're_exported';
}

/// A top-level getter re-exported via re_export_barrel.dart.
///
/// Must NOT be reported as unused — the re-export makes it part of the
/// public API even if no file inside the project directly references it.
int get reExportedGetter => 42;

/// A top-level setter re-exported via re_export_barrel.dart.
///
/// Must NOT be reported as unused.
set reExportedSetter(int _value) {}

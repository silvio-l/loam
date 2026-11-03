// ignore_for_file: public_member_api_docs
import 'package:meta/meta.dart';

/// A project-local marker, configured via `unused_public_exports.annotations`.
class Keep {
  const Keep();
}

/// Dependency-free marker built on dart:core: `@pragma('loam:reserved')`.
@pragma('loam:reserved')
class ReservedByPragma {}

/// Marked with the project-local annotation (only exempt when configured).
@Keep()
class ReservedByKeep {}

/// Not annotated and never referenced: a real unused export.
class TrulyUnused {}

/// Used by bin/main.dart.
class Host {
  /// Extension point for subclasses.
  @protected
  void hook() {}

  /// Not annotated and never called: a real unused member.
  void deadMember() {}

  /// Called from bin/main.dart.
  void used() {}
}

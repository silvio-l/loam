// Negative fixture (AC4 — alias/codegen counter-example):
// Local class named TextField that is NOT package:flutter — rule must NOT fire.
// Verifies Invariant 1: element model, not name matching.

/// A locally-defined text input widget — not Flutter's TextField class.
/// The loam.dev rule uses the resolved element model; it must ignore this.
class TextField {
  /// Creates a local [TextField].
  const TextField({this.decoration});

  /// Decoration (local type, not Flutter's InputDecoration).
  final Object? decoration;
}

/// Instantiation of the local (non-Flutter) TextField — zero findings expected.
Object buildAliasedField() => const TextField();

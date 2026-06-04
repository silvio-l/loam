/// Library with a generated part directive — NARROWED structural fallback.
///
/// A generated `part '*.g.dart'` at library level is NOT sufficient on its own
/// to classify a class as a code-gen input: Riverpod/freezed routinely colocate
/// plain hand-written classes in the SAME library file as a generated
/// counterpart. Only a class that itself binds a generated `_$`-counterpart
/// (`extends _$X` / `with _$X`) is a code-gen input via this fallback. Plain
/// colocated classes stay candidates (FN-protection).
library;

part 'part_heuristic.g.dart';

/// Riverpod-style notifier that binds its generated counterpart `_$…`.
/// Its public members are consumed by the generator → code-gen input (fallback).
class PartHeuristicNotifier extends _$PartHeuristicNotifier {
  /// A public method — classified as code-gen input via the narrowed fallback.
  String heuristicMethod() => 'heuristic';
}

/// A PLAIN hand-written class colocated in the SAME part-bearing library.
/// It does NOT bind a generated counterpart → must stay a candidate.
///
/// Mirrors Hellerio's `PremiumEntitlement`, a hand-written data class living in
/// `premium_provider.dart` next to a `@riverpod` notifier (which pulls in
/// `part 'premium_provider.g.dart'`). The over-broad library-level fallback used
/// to suppress such classes — this fixture is the regression guard.
class PlainColocatedClass {
  /// Genuine unused public field — MUST still be reported.
  final String colocatedLabel;
  const PlainColocatedClass(this.colocatedLabel);
}

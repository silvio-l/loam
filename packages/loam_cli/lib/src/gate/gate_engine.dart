import '../baseline/baseline_diff.dart';

/// The gate evaluation mode.
///
/// [ratchet] (default): only NEW findings fail the gate; kept and fixed legacy
///   findings are transparent.
/// [absolute]: evaluated against fixed thresholds (Slice 04 — NOT YET built).
enum GateMode {
  /// Default CI gate mode: only new findings (not in baseline) fail.
  ratchet,

  /// Absolute threshold mode — not implemented in this slice.
  absolute,
}

/// The outcome of a [GateEngine.evaluate] call.
///
/// [passed] drives the CI exit code: true → [exitCode] 0, false → [exitCode] 1.
class GateResult {
  const GateResult({
    required this.passed,
    required this.newCount,
    required this.keptCount,
    required this.fixedCount,
  });

  /// Whether the gate passed (no new findings in ratchet mode).
  final bool passed;

  /// 0 when [passed], 1 when !passed.
  int get exitCode => passed ? 0 : 1;

  /// Number of findings that are new (not in the baseline).
  final int newCount;

  /// Number of findings that are kept (present in both current run and baseline).
  final int keptCount;

  /// Number of findings that were fixed (present in baseline but not in current run).
  final int fixedCount;
}

/// Evaluates a [BaselineDiff] and returns a [GateResult] for CI.
///
/// The engine is stateless and const-constructible — share one instance freely.
///
/// **Ratchet mode** (default, Invariant 3):
///   - `passed = newFindings.isEmpty`
///   - kept and fixed findings are always transparent (legacy)
///
/// **Absolute mode** is not implemented in this slice (Slice 04).
class GateEngine {
  const GateEngine();

  /// Evaluates [diff] against the selected [mode].
  ///
  /// Returns a [GateResult] with [GateResult.passed] / [GateResult.exitCode]
  /// and the breakdown counts. Never throws.
  GateResult evaluate({required BaselineDiff diff, required GateMode mode}) {
    switch (mode) {
      case GateMode.ratchet:
        return GateResult(
          passed: diff.newFindings.isEmpty,
          newCount: diff.newFindings.length,
          keptCount: diff.keptFindings.length,
          fixedCount: diff.fixedFindings.length,
        );
      case GateMode.absolute:
        // Absolute mode is Slice 04 — not implemented yet.
        throw UnimplementedError(
          'GateMode.absolute is not implemented in this slice. '
          'Use GateMode.ratchet or wait for Slice 04.',
        );
    }
  }
}

import '../baseline/baseline_diff.dart';
import '../model/finding.dart';

/// The gate evaluation mode.
///
/// [ratchet] (default): only NEW findings fail the gate; kept and fixed legacy
///   findings are transparent.
/// [absolute]: all current findings are evaluated against a fixed [threshold]
///   — the baseline is ignored entirely (Slice 04).
enum GateMode {
  /// Default CI gate mode: only new findings (not in baseline) fail.
  ratchet,

  /// Absolute threshold mode: total current findings ≤ threshold → passed.
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

  /// Number of findings that are new (not in the baseline), or total findings
  /// in absolute mode.
  final int newCount;

  /// Number of findings that are kept (present in both current run and baseline).
  /// Always 0 in absolute mode (baseline is not consulted).
  final int keptCount;

  /// Number of findings that were fixed (present in baseline but not in current run).
  /// Always 0 in absolute mode (baseline is not consulted).
  final int fixedCount;
}

/// Evaluates findings and returns a [GateResult] for CI.
///
/// The engine is stateless and const-constructible — share one instance freely.
///
/// **Ratchet mode** (default, Invariant 3):
///   - Requires [diff].
///   - `passed = newFindings.isEmpty`
///   - kept and fixed findings are always transparent (legacy).
///
/// **Absolute mode** (Slice 04):
///   - Requires [findings]; [diff] is ignored / not needed.
///   - `passed = findings.length <= threshold` (default threshold **0**).
///   - The baseline is never read — pass the raw [List<Finding>] from
///     [AnalysisRunner.run] directly.
class GateEngine {
  const GateEngine();

  /// Evaluates the gate for [mode].
  ///
  /// - [mode] == [GateMode.ratchet]: requires [diff]; [findings]/[threshold]
  ///   are ignored.
  /// - [mode] == [GateMode.absolute]: requires [findings]; [diff] is not
  ///   consulted and may be omitted. [threshold] defaults to **0**.
  ///
  /// Returns a [GateResult] with [GateResult.passed] / [GateResult.exitCode]
  /// and the breakdown counts. Never throws.
  GateResult evaluate({
    required GateMode mode,
    BaselineDiff? diff,
    List<Finding>? findings,
    int threshold = 0,
  }) {
    switch (mode) {
      case GateMode.ratchet:
        final d = diff!;
        return GateResult(
          passed: d.newFindings.isEmpty,
          newCount: d.newFindings.length,
          keptCount: d.keptFindings.length,
          fixedCount: d.fixedFindings.length,
        );
      case GateMode.absolute:
        final total = (findings ?? []).length;
        return GateResult(
          passed: total <= threshold,
          newCount: total,
          keptCount: 0,
          fixedCount: 0,
        );
    }
  }
}

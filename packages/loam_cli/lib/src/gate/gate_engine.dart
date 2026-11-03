import '../baseline/baseline_diff.dart';
import '../model/finding.dart';
import '../rules/rule_profile.dart';

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
  /// Creates a [GateResult].
  const GateResult({
    required this.passed,
    required this.newCount,
    required this.keptCount,
    required this.fixedCount,
    this.advisoryCount = 0,
  });

  /// Whether the gate passed (no new findings in ratchet mode, and — with
  /// `strictStale` — no stale baseline entries).
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

  /// Findings that would have counted as new (ratchet) or present (absolute)
  /// but belong to a rule outside the active profile. They never change
  /// [passed]; the CLI shows them as a hint.
  final int advisoryCount;
}

/// Evaluates findings and returns a [GateResult] for CI.
///
/// The engine is stateless and const-constructible — share one instance freely.
///
/// **Ratchet mode** (default, Invariant 3):
///   - Requires [diff].
///   - `passed = newFindings.isEmpty` (and, with `strictStale`, no fixed ones)
///   - kept and fixed findings are transparent (legacy), unless `strictStale`
///     is set.
///
/// **Absolute mode** (Slice 04):
///   - Requires [findings]; [diff] is ignored / not needed.
///   - `passed = findings.length <= threshold` (default threshold **0**).
///   - The baseline is never read — pass the raw [List<Finding>] from
///     [AnalysisRunner.run] directly.
class GateEngine {
  /// Creates a [GateEngine].
  const GateEngine();

  /// Evaluates the gate for [mode].
  ///
  /// - [mode] == [GateMode.ratchet]: requires [diff]; [findings]/[threshold]
  ///   are ignored.
  /// - [mode] == [GateMode.absolute]: requires [findings]; [diff] is not
  ///   consulted and may be omitted. [threshold] defaults to **0**.
  ///
  /// [profile]: only findings of rules that [RuleProfile.blocks] count toward
  /// the decision; the rest become [GateResult.advisoryCount]. `null` means no
  /// filtering (every rule blocks).
  /// [strictStale] (ratchet only): stale baseline entries
  /// ([BaselineDiff.fixedFindings]) fail the gate as well. Off by default —
  /// improvements are then transparent.
  ///
  /// Returns a [GateResult] with [GateResult.passed] / [GateResult.exitCode]
  /// and the breakdown counts. Never throws.
  GateResult evaluate({
    required GateMode mode,
    BaselineDiff? diff,
    List<Finding>? findings,
    int threshold = 0,
    RuleProfile? profile,
    bool strictStale = false,
  }) {
    bool blocking(Finding f) => profile == null || profile.blocks(f.ruleId);
    switch (mode) {
      case GateMode.ratchet:
        final d = diff!;
        final blockingNew = d.newFindings.where(blocking).length;
        return GateResult(
          passed:
              blockingNew == 0 && !(strictStale && d.fixedFindings.isNotEmpty),
          newCount: blockingNew,
          advisoryCount: d.newFindings.length - blockingNew,
          keptCount: d.keptFindings.length,
          fixedCount: d.fixedFindings.length,
        );
      case GateMode.absolute:
        final all = findings ?? [];
        final total = all.where(blocking).length;
        return GateResult(
          passed: total <= threshold,
          newCount: total,
          advisoryCount: all.length - total,
          keptCount: 0,
          fixedCount: 0,
        );
    }
  }
}

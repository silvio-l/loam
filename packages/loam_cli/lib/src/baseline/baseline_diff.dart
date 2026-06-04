import '../model/finding.dart';
import 'baseline.dart';

/// The result of comparing a current [List<Finding>] against a frozen
/// [Baseline] — classified exclusively by [Finding.fingerprint] (Invariant 3).
///
/// Set semantics:
/// - [newFindings]   = current ∖ baseline   (fingerprints present only in current)
/// - [keptFindings]  = current ∩ baseline   (fingerprints in both)
/// - [fixedFindings] = baseline ∖ current   (fingerprints present only in baseline)
///
/// Position (line/column) is intentionally ignored — a pure line-shift keeps a
/// finding in [keptFindings], not [newFindings], because the fingerprint is
/// position-robust.
class BaselineDiff {
  const BaselineDiff({
    required this.newFindings,
    required this.keptFindings,
    required this.fixedFindings,
  });

  /// Findings that appear in the current run but NOT in the baseline.
  ///
  /// These are the only findings that can fail the ratchet gate.
  final List<Finding> newFindings;

  /// Findings that appear in both the current run and the baseline.
  ///
  /// Legacy findings — intentionally frozen; never fail the ratchet gate.
  final List<Finding> keptFindings;

  /// Findings that were in the baseline but NO LONGER appear in the current run.
  ///
  /// Represents improvements — never fail the gate.
  final List<BaselineFinding> fixedFindings;
}

/// Rule profiles: which rules may block the gate (issue #12, ADR-0006).
///
/// A profile decides only what the **gate** treats as blocking. Every rule
/// still runs and every finding is still recorded in the baseline, so
/// switching profile never changes `baseline.json` or the ruleset hash.
enum RuleProfile {
  /// Rules with a near-zero false-positive rate. The default.
  core,

  /// Everything in [core] plus the heuristic and threshold-based rules.
  strict;

  /// Parses a profile name (`core` | `strict`), or `null` when unknown.
  static RuleProfile? tryParse(String name) {
    for (final profile in values) {
      if (profile.name == name) return profile;
    }
    return null;
  }

  /// The profile used when neither the CLI nor `loam.yaml` names one.
  static const RuleProfile defaultProfile = core;

  /// Resolves the effective profile. Precedence: [cli] > [config] > default.
  static RuleProfile resolve({RuleProfile? cli, RuleProfile? config}) =>
      cli ?? config ?? defaultProfile;

  /// Whether a finding of [ruleId] may block the gate under this profile.
  ///
  /// A rule without an entry in [kRuleProfiles] counts as [strict]-only, so a
  /// new rule never blocks by default before someone classified it.
  bool blocks(String ruleId) =>
      index >= (kRuleProfiles[ruleId] ?? RuleProfile.strict).index;
}

/// The single source of truth: the lowest profile in which a rule blocks.
///
/// Placement follows the product rule in `internal-notes`: a finding in
/// `core` must be one a developer can trust blindly.
///
/// - `core`: exact checks on the resolved element model or on syntax nodes
///   with documented conservative exclusions. `architecture-boundaries` is
///   exact too: it only fires for a boundary the project wrote into
///   `loam.yaml`, never for a guessed one.
/// - `strict`: text heuristics (comments), thresholds that are a judgement
///   call (duplicates, complexity), and widget-local accessibility checks
///   that cannot see semantics added by a project's own wrapper widgets.
const Map<String, RuleProfile> kRuleProfiles = {
  'architecture-boundaries': RuleProfile.core,
  'circular-dependencies': RuleProfile.core,
  'hardcoded-secrets': RuleProfile.core,
  'slop-empty-catch': RuleProfile.core,
  'slop-tautological-assertion': RuleProfile.core,
  'slop-unjustified-ignore': RuleProfile.core,
  'unused-public-exports': RuleProfile.core,
  'a11y-form-field-label': RuleProfile.strict,
  'a11y-icon-button-label': RuleProfile.strict,
  'a11y-image-label': RuleProfile.strict,
  'a11y-interactive-semantics': RuleProfile.strict,
  'code-duplicates': RuleProfile.strict,
  'complexity-hotspots': RuleProfile.strict,
  'slop-assertion-free-test': RuleProfile.strict,
  'slop-narrative-comment': RuleProfile.strict,
  'slop-placeholder-comment': RuleProfile.strict,
  'slop-setstate-after-async-gap': RuleProfile.strict,
  'slop-undisposed-resource': RuleProfile.strict,
  'slop-unimplemented-stub': RuleProfile.strict,
  'slop-workflow-narration-comment': RuleProfile.strict,
};

import '../model/finding.dart';

/// Explicit, human-readable version marker for [kGuidanceCorpus].
///
/// Analogous to `kPromptVersion` in `fix_prompt_template.dart` (CONTEXT.md's
/// `prompt@ver`, Invariant 5 — reproducibility). Any content change to
/// [kGuidanceCorpus] (a rewritten, added, or removed guidance text) must bump
/// this marker to a new version (e.g. `guidance@v2`).
const String kGuidanceVersion = 'guidance@v1';

/// One preventive, agent-addressed recommendation for a fired rule class.
///
/// Distinct from a [Finding]: a [Finding] describes one concrete occurrence
/// at a file/line; a [Recommendation] describes how to avoid the whole
/// *class* of finding in the future — exactly one per distinct `ruleId`, no
/// matter how many times that rule fired in the current run.
class Recommendation {
  /// Creates a [Recommendation].
  const Recommendation({required this.ruleId, required this.guidance});

  /// The rule ID this recommendation applies to (e.g. `unused-public-exports`).
  final String ruleId;

  /// Curated, agent-addressed guidance text — "how to avoid this class of
  /// finding going forward". Phrased as an instruction-ready snippet the
  /// agent can propose verbatim to its user for their persistent instructions
  /// (e.g. `CLAUDE.md`). loam.dev itself never writes to user instructions.
  final String guidance;
}

/// Curated, versioned preventive-guidance corpus, keyed by `ruleId`.
///
/// **Not LLM-generated** (Invariant 2 — no LLM in the scan/gate path; Free-
/// Tier-Disziplin): every entry is hand-written prose, reviewed like any other
/// code change. Guidance is addressed to the AI coding agent that is
/// consuming loam.dev's output — not directly to the human — because the
/// agent is expected to be the one proposing it to its user (and, on
/// agreement, adding it to that user's persistent instructions).
///
/// Every `ruleId` in `AnalysisRunner.fullRegistryIds` MUST have a non-empty
/// entry here — enforced by a completeness test in
/// `recommendation_engine_test.dart`, not by the type system (deliberately a
/// central map rather than a `Rule`-interface property, to keep concrete
/// `Rule` implementations free of guidance-text ownership; see issue 04).
///
/// Part of the `guidance@ver` versioning: a content change here requires
/// bumping [kGuidanceVersion].
const Map<String, String> kGuidanceCorpus = {
  'a11y-form-field-label':
      'Always give interactive text-input widgets (TextField, TextFormField) '
      'an accessible label — a non-null `labelText`/`hintText` in their '
      '`InputDecoration`, or an enclosing `Semantics(label: …)` — so screen '
      'readers can announce what the field is for.',
  'a11y-icon-button-label':
      'Give every icon-only interactive widget (IconButton, or a '
      'GestureDetector/InkWell wrapping just an Icon) a `tooltip` or an '
      'enclosing `Semantics(label: …)` that names its action — the icon alone '
      'carries no accessible name for screen reader users.',
  'a11y-image-label':
      'Set `semanticLabel` on every `Image` that conveys meaning; mark purely '
      'decorative images with `excludeFromSemantics: true` so screen readers '
      'skip them on purpose instead of announcing nothing useful.',
  'a11y-interactive-semantics':
      'Wrap custom interactive widgets (anything with `onTap`/`onPressed`/'
      '`onLongPress` that is not already a built-in Flutter interactive '
      'widget) in `Semantics(label: …)` so assistive technology can identify '
      'them and announce their purpose.',
  'circular-dependencies':
      'Keep first-party imports flowing one way between libraries — before '
      'adding a new cross-file import, check whether it would close a cycle '
      'with an existing import chain, and extract a shared abstraction '
      'instead of adding a back-reference.',
  'code-duplicates':
      'Before pasting a block of logic into a second location, extract it '
      'into a shared function/widget/mixin first — duplicated implementation '
      'logic drifts out of sync the moment one copy gets fixed and the other '
      'does not.',
  'complexity-hotspots':
      'Keep functions small and single-purpose as you write them: extract a '
      'helper as soon as a function accumulates several nested conditionals '
      'or branches, rather than letting cyclomatic/cognitive complexity grow '
      'to the point where it needs a later refactor.',
  'slop-empty-catch':
      'Never leave a `catch` block empty (or comment-only) — log the error, '
      'rethrow it, or handle it explicitly. An empty catch silently swallows '
      'failures that resurface later as much harder bugs to diagnose.',
  'slop-narrative-comment':
      'Write comments that explain *why* a decision was made, not comments '
      'that restate *what* the next line already says (e.g. `// increment '
      'counter` above `counter++`) — narrative comments are noise that rots '
      'as the code around them changes.',
  'slop-unjustified-ignore':
      'Never add an `// ignore:`/`// loam-ignore:` suppression without a '
      'comment justifying why the finding is a false positive or '
      'intentional — an unjustified ignore hides a real issue from every '
      'future reviewer.',
  'unused-public-exports':
      'Before adding a new public top-level declaration under `lib/`, make '
      'sure something actually references it (or it is a deliberate package '
      'export) — unused public exports accumulate as dead surface area that '
      'nobody notices until it goes stale.',
};

/// Pure aggregation module: findings in, curated preventive recommendations
/// out.
///
/// No LLM call, no I/O (Invariant 2). Deterministic (Invariant 5): the same
/// [Finding]s always produce the same [Recommendation]s in the same order.
/// The engine is stateless and const-constructible — share one instance
/// freely (mirrors [GateEngine]/`BaselineEngine`).
class RecommendationEngine {
  /// Creates a [RecommendationEngine].
  const RecommendationEngine();

  /// Returns one [Recommendation] per distinct `ruleId` present in
  /// [findings] — deduplicated even when a rule fired many times — sorted
  /// lexicographically by `ruleId` for determinism.
  ///
  /// Returns an empty list when [findings] is empty (no findings ⇒ no
  /// preventive-recommendation block, avoiding empty-run noise). A `ruleId`
  /// absent from [kGuidanceCorpus] is skipped rather than crashing, so a
  /// findings list from an unrecognised/future rule never breaks rendering.
  List<Recommendation> recommend(List<Finding> findings) {
    final ruleIds = <String>{for (final f in findings) f.ruleId};
    final sortedIds = ruleIds.toList()..sort();
    return [
      for (final ruleId in sortedIds)
        if (kGuidanceCorpus[ruleId] case final guidance?)
          Recommendation(ruleId: ruleId, guidance: guidance),
    ];
  }
}

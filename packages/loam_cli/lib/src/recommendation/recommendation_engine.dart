import '../model/finding.dart';

/// Explicit, human-readable version marker for [kGuidanceCorpus].
///
/// Analogous to `kPromptVersion` in `fix_prompt_template.dart` (internal-notes's
/// `prompt@ver`, Invariant 5 — reproducibility). Any content change to
/// [kGuidanceCorpus] (a rewritten, added, or removed guidance text) must bump
/// this marker to a new version (e.g. `guidance@v2`).
const String kGuidanceVersion = 'guidance@v2';

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
  'architecture-boundaries':
      'Respect the layer boundaries declared in loam.yaml — before adding an '
      'import across layers, check that the importing layer is allowed to '
      'depend on the target layer, and put shared contracts into a layer both '
      'sides may import instead of reaching into a forbidden one.',
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
  'hardcoded-secrets':
      'Never write API keys, passwords, or tokens into source as string '
      'literals — read them at runtime (`String.fromEnvironment`, '
      '`Platform.environment`, or a secret store) and rotate any credential '
      'that was ever committed.',
  'slop-empty-catch':
      'Never leave a `catch` block empty (or comment-only) — log the error, '
      'rethrow it, or handle it explicitly. An empty catch silently swallows '
      'failures that resurface later as much harder bugs to diagnose. If '
      'ignoring is deliberate, write `catch (_) {}`.',
  'slop-narrative-comment':
      'Write comments that explain *why* a decision was made, not comments '
      'that restate *what* the next line already says (e.g. `// increment '
      'counter` above `counter++`) — narrative comments are noise that rots '
      'as the code around them changes. This also covers decorative banner/'
      'divider comments, bare category labels (`// Main logic`, `// Helper '
      'function`), emoji-only decoration, redundant end-of-block markers '
      '(`// end if`), and vague TODOs with no concrete action, condition, or '
      'reference — give a TODO real scope or remove it.',
  'slop-placeholder-comment':
      'Never leave a placeholder such as `// ... rest of code` or `// your '
      'code here` in place of code — write out the full implementation, or '
      'delete the marker if nothing belongs there.',
  'slop-setstate-after-async-gap':
      'After every `await` in a `State`, check `if (!mounted) return;` '
      'before calling `setState` — the screen may have been closed while '
      'the future ran, and `setState` on an unmounted state throws.',
  'slop-tautological-assertion':
      'Never write an assertion that cannot fail — `expect(true, isTrue)`, '
      '`expect(1, 1)` or `expect(x, x)` stay green whatever the code does. '
      'Assert on a value the code under test produced, or delete the check.',
  'slop-undisposed-resource':
      'Whatever a `State` creates (controllers, focus nodes, notifiers, '
      'timers, subscriptions), release in `dispose()` — `dispose()`, '
      '`close()` or `cancel()` — otherwise it keeps listeners and timers '
      'alive after the widget is gone.',
  'slop-assertion-free-test':
      'Every `test`/`testWidgets` must assert something — `expect`, '
      '`verify` or `check` on a value the code under test produced. A body '
      'that only calls the code proves nothing; if "does not throw" is the '
      'point, write `expect(() => ..., returnsNormally)`.',
  'slop-unimplemented-stub':
      'Do not leave a function or method whose whole body is `throw '
      'UnimplementedError()` in production code — implement it, make it '
      'abstract, or throw `UnsupportedError` with a reason if it is '
      'deliberately unsupported.',
  'slop-unjustified-ignore':
      'Never add an `// ignore:`/`// loam-ignore:` suppression without a '
      'comment justifying why the finding is a false positive or '
      'intentional — an unjustified ignore hides a real issue from every '
      'future reviewer.',
  'slop-workflow-narration-comment':
      'Do not narrate a function body step-by-step with `// Step 1: …`, `// '
      'Step 2: …`, `// First, …`, `// Next, …`, `// Then, …`, `// Finally, '
      '…` comments — if the statements need that much walking-through, '
      'extract well-named helper functions instead of adding a running '
      'commentary on top of self-explanatory code.',
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

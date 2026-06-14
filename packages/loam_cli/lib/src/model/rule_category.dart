/// The high-level category a [Rule] belongs to.
///
/// Three categories, corresponding to loam.dev's three analysis pillars
/// (see CONTEXT.md for the canonical definitions):
///
/// - [drift] — structural-drift detectors (circular dependencies, unused
///   public exports, code duplicates, complexity hotspots …).
/// - [slop] — AI-slop detectors (empty catch blocks, filler comments,
///   dead guards …).
/// - [accessibility] — WCAG-relevance Flutter-widget detectors (`loam a11y`).
///
/// The `a11y-` ruleId prefix used by accessibility rules is a **naming
/// convention for humans** — category membership is determined exclusively by
/// this enum, never by string-prefix matching (Invariant 1).
enum RuleCategory {
  /// Structural-drift detectors — circular dependencies, unused public
  /// exports, code duplicates, complexity hotspots, …
  drift,

  /// AI-slop detectors — empty catch blocks, filler comments, dead guards, …
  slop,

  /// WCAG-relevance Flutter-widget detectors for `loam a11y`.
  accessibility,
}

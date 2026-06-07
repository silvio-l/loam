/// A public class with a `// loam-ignore:` directive that has NO reason text.
///
/// Grund-Pflicht: this directive must be REJECTED (no reason → invalid).
/// The class must still be reported as unused.
// loam-ignore: unused-public-exports
class NoReasonDirective {}

/// A public class with a `// loam-ignore:` directive that has NO rule ID.
///
/// A directive without a rule ID must be REJECTED — nothing is suppressed.
// loam-ignore:
class NoRuleIdDirective {}

/// A public class with a directive for a DIFFERENT rule ID.
///
/// The wrong rule ID must NOT suppress the `unused-public-exports` finding.
// loam-ignore: some-other-rule – Wrong rule; this class is still unused
class WrongRuleDirective {}

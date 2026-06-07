/// A public class suppressed via a same-line `// loam-ignore:` directive.
///
/// The directive appears on the SAME line as the declaration. The rule
/// `unused-public-exports` should NOT report this class.
class SuppressedSameLine {} // loam-ignore: unused-public-exports – Intentionally not exported; used only at runtime via reflection

/// A public class suppressed on the PRECEDING line.
// loam-ignore: unused-public-exports – Plugin API: consumed by the generated plugin registry
class SuppressedPrecedingLine {}

/// A public class with NO suppress directive — must be reported as unused.
class NotSuppressed {}

/// Another unsuppressed class to verify that only the exact ruleId is targeted.
class AlsoNotSuppressed {}

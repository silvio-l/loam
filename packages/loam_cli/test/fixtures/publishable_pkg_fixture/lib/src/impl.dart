/// A public class in lib/src/ (internal by convention).
///
/// This symbol is NOT re-exported by any barrel file. On a publishable package,
/// lib/src/ symbols that are not re-exported are still *internally dead* and
/// must continue to be reported as unused-public-exports.
class InternalSrcClass {}

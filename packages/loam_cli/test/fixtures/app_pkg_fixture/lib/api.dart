/// A public class declared in lib/ of an app (publish_to: none).
///
/// In app mode, unused public symbols are always reported — the lib/ API is
/// not intentionally exposed to external consumers. This class must be reported
/// as unused-public-exports when it has no references within the package.
class AppLibClass {}

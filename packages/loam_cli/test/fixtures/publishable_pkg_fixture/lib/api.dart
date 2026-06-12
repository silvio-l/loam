/// A public class declared directly in lib/ (not lib/src/).
///
/// On a publishable package (no publish_to: none) this symbol is part of the
/// intentional public API — external consumers can import it via
/// `package:publishable_pkg_fixture/api.dart`. It must NOT be reported as
/// unused-public-exports even though it has no references within this package.
class PublishableLibClass {}

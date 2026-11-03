/// Suppressed and still needed: counted, not reported.
// loam-ignore: unused-public-exports – Plugin API, consumed reflectively
class ActiveSuppression {}

/// Expired on 2026-01-01: stops suppressing.
// loam-ignore: unused-public-exports until=2026-01-01 – Temporary, remove after the migration
class ExpiredSuppression {}

/// Not yet expired: keeps suppressing.
// loam-ignore: unused-public-exports until=2099-12-31 – Temporary, remove after the migration
class FutureSuppression {}

/// Used by bin/main.dart, so its directive is stale.
// loam-ignore: unused-public-exports – Stale: this class is used by bin/main.dart
class UsedClass {}

/// No reason given: suppresses nothing.
// loam-ignore: unused-public-exports
class MissingReason {}

/// Typo in the rule ID.
// loam-ignore: no-such-rule – Typo in the rule ID
class UnknownRule {}

/// Impossible calendar date.
// loam-ignore: unused-public-exports until=2026-13-45 – Not a real date
class InvalidExpiry {}

/// Directive without any rule ID.
// loam-ignore:
class MissingRule {}

/// `until=` after the reason starts: plain text, never expires.
// loam-ignore: unused-public-exports – Temporary until=2026-01-01
class MisplacedExpiry {}

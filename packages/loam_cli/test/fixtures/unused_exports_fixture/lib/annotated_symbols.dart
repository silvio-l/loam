import 'package:meta/meta.dart';

/// A class annotated with @visibleForTesting.
/// Must NOT be reported as unused (conservative annotation exclusion).
@visibleForTesting
class VisibleForTestingClass {
  String get name => 'visible_for_testing';
}

/// A class annotated with @pragma.
/// Must NOT be reported as unused (conservative annotation exclusion).
@pragma('vm:entry-point')
class PragmaAnnotatedClass {
  String get name => 'pragma_annotated';
}

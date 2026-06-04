/// Plain class with unused public members — must still be reported.
///
/// This is the FN-protection fixture: a normal class with no code-gen markers
/// must NOT be excluded by the CodegenInputClassifier.
library;

/// A plain class with no code-gen markers.
/// Its unused public members MUST still be reported.
class PlainClass {
  /// A public field that is truly never referenced anywhere — MUST be reported.
  final String unusedField = 'unused';

  /// A public method that is truly never referenced anywhere — MUST be reported.
  String unusedMethod() => 'unused';
}

/// Another plain class — used to verify that PlainClass.unusedField is indeed
/// not referenced (only PlainClass itself is referenced, not its members).
class PlainConsumer {
  final PlainClass? instance;
  const PlainConsumer({this.instance});
}

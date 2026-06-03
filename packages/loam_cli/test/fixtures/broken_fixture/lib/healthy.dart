/// A perfectly valid Dart file in the broken fixture.
class HealthyClass {
  const HealthyClass(this.name);

  final String name;

  String greet() => 'Hello, $name!';
}

// Positive fixture: members whose whole body is the stub.

/// Concrete class with stubs.
class Repository {
  /// Expression body stub.
  int load() => throw UnimplementedError();

  /// Block body stub with a message.
  void save() {
    throw UnimplementedError('TODO');
  }

  /// Getter stub.
  String get name => throw UnimplementedError();

  /// Setter stub.
  set name(String value) => throw UnimplementedError();
}

/// Top-level stub.
void syncAll() {
  throw UnimplementedError();
}

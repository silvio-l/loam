// ignore_for_file: unused_element – fixture declarations are loaded by ProjectLoader only.

void _processRequest(int id) {
  // First, look up the request
  final request = _lookup(id);
  // Next, run the validators
  _runValidators(request);
  // Then, persist the result
  _persist(request);
}

Object? _lookup(int id) => null;
void _runValidators(Object? request) {}
void _persist(Object? request) {}

// ignore_for_file: unused_element – fixture declarations are loaded by ProjectLoader only.

class _Session {
  _Session(String token) {
    // Step 1: decode the token
    _decode(token);
    // Then, register the session
    _register();
  }

  void _decode(String token) {}
  void _register() {}
}

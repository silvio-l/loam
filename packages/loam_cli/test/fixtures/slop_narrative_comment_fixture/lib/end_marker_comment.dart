// ignore_for_file: unused_element – fixture declarations are loaded by ProjectLoader only.

class _Loop {
  void _run() {
    for (var i = 0; i < 3; i++) {
      _tick(i);
      // end for loop
    }
  }

  void _tick(int i) {}

  void _branch() {
    if (true) {
      _tick(0);
    }
    // end if
  }

  void _named() {
    _finish();
    // End processOrder
  }

  void _finish() {}

  void _describe() {
    _submit();
    // end date validation logic goes here before submission
  }

  void _submit() {}
}

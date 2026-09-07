// ignore_for_file: unused_element – fixture declarations are loaded by ProjectLoader only.

// Negative fixture: a single narrated step is not evidence of a walkthrough.
class _Checkout {
  void _finalize() {
    // First, make sure the cart is not empty
    _assertNotEmpty();
    _charge();
    _confirm();
  }

  void _assertNotEmpty() {}
  void _charge() {}
  void _confirm() {}
}

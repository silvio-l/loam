// ignore_for_file: unused_element – fixture declarations are loaded by ProjectLoader only.

class _OrderService {
  void _placeOrder() {
    // Step 1: validate the order
    _validate();
    // Step 2: charge the customer
    _charge();
    // Finally, send the confirmation email
    _sendConfirmation();
  }

  void _validate() {}
  void _charge() {}
  void _sendConfirmation() {}
}

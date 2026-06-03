import 'package:cross_file_fixture/greeter.dart';

/// Application entry-point that uses [Greeter] from greeter.dart.
///
/// The reference to [Greeter] here is the cross-file reference that the
/// ProjectLoader test must prove is fully resolved (element declared in
/// greeter.dart, used in app.dart).
class App {
  final Greeter _greeter = Greeter();

  /// Runs the application.
  void run() {
    print(_greeter.greet('World'));
  }
}

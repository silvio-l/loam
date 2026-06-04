import 'package:unused_exports_fixture/consumer.dart';

/// Entrypoint — main is never an unused-export candidate.
void main() {
  final c = Consumer();
  print(c.consume());
}

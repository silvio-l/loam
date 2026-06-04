import 'package:unused_exports_fixture/consumer.dart';
import 'package:unused_exports_fixture/kinds_consumer.dart';

/// Entrypoint — main is never an unused-export candidate.
void main() {
  final c = Consumer();
  print(c.consume());
  // Reference KindsConsumer so it is not reported as unused.
  final k = KindsConsumer();
  print(k.callFunction());
}

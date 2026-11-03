// Entry point — uses only `UsedClass` from lib/, so every other lib/ class
// stays unused and triggers an `unused-public-exports` finding.
import 'package:suppression_audit_fixture/audit.dart';

void main() => UsedClass();

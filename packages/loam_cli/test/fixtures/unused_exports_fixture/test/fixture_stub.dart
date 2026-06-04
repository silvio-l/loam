// Stub test file — present so ProjectLoader can discover the test/ directory
// and prove that test/ references count as usage in the UsageIndex.
// NOT intended to be run by the loam_cli test runner.
import 'package:unused_exports_fixture/test_only_class.dart';

void main() {
  // Reference TestOnlyClass so the UsageIndex sees it as referenced from test/.
  TestOnlyClass();
}

// Stub tool script — present so ProjectLoader can discover tool/ files
// and prove that tool/ references count as usage in the UsageIndex.
import 'package:unused_exports_fixture/test_only_class.dart';

void main() {
  // Reference ToolOnlyClass so the UsageIndex sees it as referenced from tool/.
  ToolOnlyClass();
}

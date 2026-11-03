import 'dart:io';

import 'package:loam/src/loader/project_loader.dart';

/// Makes every project loaded by this test file share one analyzer store, so
/// the SDK summaries are built once per machine instead of once per temporary
/// project. Call it first in `main()`. Not for tests that assert the
/// per-project store or "caching off" itself.
void useSharedAnalyzerStore() {
  ProjectLoader.testCacheDirectory =
      '${Directory.systemTemp.path}/loam_test_analyzer_store';
}

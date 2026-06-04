/// A public class referenced only from test/.
/// Should NOT be reported (test references count as usage).
class TestOnlyClass {
  String get name => 'test_only';
}

/// A public class referenced only from tool/.
/// Should NOT be reported (tool references count as usage).
class ToolOnlyClass {
  String get name => 'tool_only';
}

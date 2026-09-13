## 2024-05-24 - Dart map putIfAbsent performance in tight loops
**Learning:** `Map.putIfAbsent` with anonymous closures causes excessive garbage collection and closure allocations when used in tight loops (like AST processing), creating a significant performance bottleneck.
**Action:** Prefer manual map lookups (`var val = map[key]; if (val == null) { map[key] = compute(); }`) instead of `putIfAbsent` in hot paths/tight loops in Dart.

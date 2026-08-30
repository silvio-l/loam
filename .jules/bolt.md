## 2024-05-24 - Avoid `Map.putIfAbsent` with closures in tight loops
**Learning:** Dart's `Map.putIfAbsent` creates closure objects every iteration if an anonymous function is passed as the second argument, which causes excessive garbage collection and closure allocations in tight loops (like AST processing or data grouping).
**Action:** Use manual map lookups (e.g. `var value = map[key]; if (value == null) { map[key] = value = ... }`) instead of `putIfAbsent` in hot paths.

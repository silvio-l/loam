## 2024-08-23 - [Dart putIfAbsent overhead]
**Learning:** Dart's `Map.putIfAbsent` involves a closure allocation and invocation if the key is missing, which adds measurable overhead when used inside tight inner loops (e.g., iterating through thousands of tokens in an AST visitor).
**Action:** Replace `putIfAbsent` with manual `var val = map[key]; if (val == null) { ... }` checks in hot paths to avoid per-iteration closure allocation.

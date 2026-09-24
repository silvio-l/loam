## 2026-09-24 - Replace Map.putIfAbsent in tight loops to avoid closure allocations
**Learning:** In Dart, using `Map.putIfAbsent` with an anonymous closure in tight loops (like AST processing in `duplicate_code_collector.dart`) causes excessive garbage collection and closure allocations, hurting performance significantly.
**Action:** Prefer manual map lookups (`var slot = map[key]; if (slot == null) { map[key] = ... }`) instead of `putIfAbsent` when iterating over many tokens or elements to avoid the overhead of closure allocation.

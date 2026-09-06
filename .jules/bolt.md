## 2026-09-06 - [Avoid `putIfAbsent` in tight Dart loops]
**Learning:** Using `Map.putIfAbsent(key, () => ...)` with an anonymous closure in tight loops (like AST processing or large iterations over arrays) causes excessive garbage collection and closure allocations in Dart, even when the key already exists.
**Action:** Replace `putIfAbsent` calls with manual map lookups (e.g., `var val = map[key]; if (val == null) { val = ...; map[key] = val; }`) in performance-critical code paths to minimize unnecessary allocations.

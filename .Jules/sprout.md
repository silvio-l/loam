## 2024-05-24 - Enforce strict English localization for CLI output
**Learning:** Found a German localization leak `(im Browser geöffnet)` in the CLI output. The CLI tool is intended for a global audience and defaults to English.
**Action:** Always ensure that CLI messages are in English. Pay close attention to hardcoded strings in print/stdout statements to avoid mixing languages.
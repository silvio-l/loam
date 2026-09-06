## 2024-05-29 - [Global Keyboard Focus]
**Learning:** Found that the app lacked explicit `:focus-visible` styles across its interactive elements (`a`, `button`), relying solely on default browser outlines or having none at all, which hurts keyboard accessibility.
**Action:** Always add a branded `:focus-visible` global style rule to the base layout/CSS reset to ensure a consistent and accessible tab-focus experience across the entire application without needing per-component overrides.

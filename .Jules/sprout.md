## 2025-02-27 - Keyboard Accessibility in Dark Themes
**Learning:** Browser default focus outlines often fail contrast tests or are entirely invisible against dark theme backgrounds, causing severe accessibility issues for keyboard users.
**Action:** When working on UI components in dark themes, always explicitly define `:focus-visible` styles for interactive elements (buttons, links). The most reliable pattern is to mirror existing `:hover` styles, including setting `outline: none;` to suppress the inadequate browser default outline.

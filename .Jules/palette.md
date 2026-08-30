## 2026-08-30 - Keyboard Navigation & Skip Links
**Learning:** The Astro layout lacked a mechanism for keyboard users to bypass the site header (logo, navigation, locale switcher) and jump straight to the main content, which is a key accessibility requirement. Furthermore, many interactive elements lacked a clear visible focus ring.
**Action:** Implemented a "Skip to main content" link that is hidden off-screen until focused, and added a global `:focus-visible` outline to all `a` and `button` tags to ensure consistent, highly visible keyboard navigation throughout the site.

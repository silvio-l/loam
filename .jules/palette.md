## 2024-08-16 - Ensure Visible Focus State Across Site
**Learning:** Adding a global `:focus-visible` rule using the brand's primary accent color (`var(--green)`) is an effective and robust way to ensure high contrast focus rings for keyboard navigation, particularly in complex dark themes where default browser outlines can easily get lost. This solves an accessibility issue without needing custom classes on every interactive element.
**Action:** Always verify a global `:focus-visible` outline is present for web projects to cover edge cases and guarantee keyboard navigation is accessible.

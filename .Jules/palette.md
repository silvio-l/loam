## 2023-10-27 - [Focus Visible Styles]
**Learning:** Added global `:focus-visible` styles to improve keyboard navigation accessibility. Found that adding custom CSS to a global file can be a valid approach when utility classes aren't feasible for a sweeping accessibility change, but must be careful not to override or conflict with existing design tokens.
**Action:** When adding global accessibility styles, carefully review existing CSS variables (like `var(--green)`) to ensure consistency with the design system. Avoid unnecessary dev dependency additions when a simple CSS rule suffices.

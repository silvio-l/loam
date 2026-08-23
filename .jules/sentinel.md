## 2024-08-23 - [Missing noopener noreferrer on target=_blank]
**Vulnerability:** A missing `noreferrer` attribute on anchor tags with `target="_blank"` was found across several pages and components (`Layout.astro`, `index.astro`, `DemoReport.astro`).
**Learning:** Modern browsers implicitly set `noopener` for `target="_blank"`, but do not block the `Referer` header automatically. Setting `rel="noopener noreferrer"` is important as a best practice to avoid exposing sensitive info or tracking parameters to external sites, which is not prevented by just `rel="noopener"`.
**Prevention:** Add a linter rule to strictly require `rel="noopener noreferrer"` whenever `target="_blank"` is used.

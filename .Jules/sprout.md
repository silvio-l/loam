## 2026-08-16 - Add copy button for rule IDs
**Learning:** The HTML reporter generates a self-contained, offline HTML file using only inline CSS and JS. Modifying its interactive elements requires carefully injecting HTML strings, styling, and JS handlers inside `lib/src/report/html_reporter.dart` while respecting structural invariant tests.
**Action:** When adding small quality-of-life UI features to the generated HTML report, follow the existing pattern of raw HTML string interpolation and inline vanilla JS to keep it zero-dependency and standalone.

## 2025-02-14 - Fix XSS in html_reporter.dart escHtml by escaping single quotes
**Vulnerability:** XSS vulnerability in `escHtml` function inside `html_reporter.dart`. Single quotes were not escaped, leaving attributes (e.g. `onclick`) vulnerable if data injected into HTML had unescaped single quotes.
**Learning:** Even simple manual implementations of string escape tools (`escHtml`) can be subtly incomplete.
**Prevention:** Use standardized escaping libraries or double-check custom escaping logic against known injection attack vectors. Always remember to update related test and security files (like CSP headers `_headers`) if the payload hash changes.

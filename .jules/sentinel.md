## 2024-08-16 - XSS in HTML Report JSON Payload
**Vulnerability:** The HTML report embedded structured findings directly as a JSON payload (`<script type="application/json">`) without escaping HTML characters. This allowed a malicious `Finding.message` containing `</script>` to break out of the script tag and execute arbitrary Javascript, resulting in Cross-Site Scripting (XSS).
**Learning:** Embedding JSON payloads in HTML documents requires escaping specific HTML characters (`<`, `>`, `&`) to their unicode escape sequence (`\u003c`, `\u003e`, `\u0026`). The Dart `JsonEncoder` does not do this out of the box.
**Prevention:** Always use a helper function to escape JSON strings before embedding them into HTML strings.

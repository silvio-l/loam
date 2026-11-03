// Negative fixture: comments that merely mention the same words.

/// Dartdoc may say "... rest of code" without being a placeholder.
///
/// ... rest of code
class Legit {
  /// Explains why.
  void a() {
    // The rest of the code path assumes the cache is warm.
    // The existing code handles retries; this branch only logs.
    // ...
    // ... but only on Tuesdays
    // other methods are not affected by this lock
    // your code here is executed on the UI thread
    const text = '// ... rest of code';
    print(text);
  }
}

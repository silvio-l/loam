// ignore_for_file: unused_element – fixture declarations are loaded by ProjectLoader only.

// ============================
class _BannerBefore {
  void _doWork() {}
}

class _WithFramedBanner {
  // ****** SECTION ******
  void _helper() {}
}

class _NegativeHyphenDivider {
  // ---------------------------
  // Plain hyphen dividers are a legitimate section-separator convention.
  void _noop() {}
}

class _NegativeInformative {
  // Handles retry with exponential backoff up to 3 attempts.
  void _retry() {}
}

class _NegativeInlineDecoration {
  // __init__ sets up the cache and __dispose__ tears it down.
  void _a() {}

  // **Note** the order matters here, see the **bold** sections above.
  void _b() {}
}

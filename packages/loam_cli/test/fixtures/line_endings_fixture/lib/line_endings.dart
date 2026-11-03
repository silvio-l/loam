/// Fixture for the line-ending regression test (issue #135): each construct
/// below yields a finding whose anchor or message reads source text, several
/// of them across line breaks. The test runs it once as committed (LF) and
/// once converted to CRLF, and expects identical findings.
library;

// =====================================================================
// Section 1 — Cards
// =====================================================================

/// A widget-like class with a tap callback.
class CustomCard {
  /// Creates a [CustomCard].
  const CustomCard({required this.onTap, this.child});

  /// Called on tap.
  final void Function() onTap;

  /// Optional content.
  final Object? child;
}

/// A tappable card without semantics; its multi-line string spans lines.
Object buildCard() => CustomCard(
  onTap: () {},
  child: '''
first line
second line
''',
);

/// A comment-only catch whose try block holds a multi-line string.
void swallow() {
  try {
    throw StateError('''
multi-line
message
''');
  } catch (e) {
    // Swallowed on purpose.
  }
}

/* ... rest of the
   code here ... */
/// Placeholder written as a block comment over two lines.
void later() {}

// ignore: unused_element
void _hidden() {}

/// Keeps [_hidden] referenced for the analyzer.
void useHidden() => _hidden();

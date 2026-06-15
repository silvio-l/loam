/// A machine-readable WCAG (Web Content Accessibility Guidelines) reference.
///
/// Carries the success criterion number, a human-readable short title,
/// and the canonical Understanding document URL. Passed through by all
/// reporters so consumers can link directly to the WCAG documentation
/// without parsing the finding message.
///
/// All currently known references are available as static constants
/// (e.g. [wcag111]).
class WcagRef {
  /// Creates a [WcagRef].
  const WcagRef({required this.number, required this.title, required this.url});

  /// The WCAG success criterion number (e.g. `'1.1.1'`).
  final String number;

  /// The short title of the success criterion (e.g. `'Non-text Content'`).
  final String title;

  /// The canonical URL of the WCAG Understanding document for this criterion.
  final String url;

  /// WCAG 1.1.1 Non-text Content.
  ///
  /// Every non-text content that is presented to the user must have a text
  /// alternative that serves the equivalent purpose.
  static const wcag111 = WcagRef(
    number: '1.1.1',
    title: 'Non-text Content',
    url: 'https://www.w3.org/WAI/WCAG21/Understanding/non-text-content.html',
  );
}

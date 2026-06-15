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

  /// WCAG 1.3.1 Info and Relationships.
  ///
  /// Information, structure, and relationships conveyed through presentation
  /// can be programmatically determined or are available in text.
  static const wcag131 = WcagRef(
    number: '1.3.1',
    title: 'Info and Relationships',
    url:
        'https://www.w3.org/WAI/WCAG21/Understanding/info-and-relationships.html',
  );

  /// WCAG 3.3.2 Labels or Instructions.
  ///
  /// Labels or instructions are provided when content requires user input.
  static const wcag332 = WcagRef(
    number: '3.3.2',
    title: 'Labels or Instructions',
    url:
        'https://www.w3.org/WAI/WCAG21/Understanding/labels-or-instructions.html',
  );

  /// WCAG 4.1.2 Name, Role, Value.
  ///
  /// For all user interface components, the name and role can be
  /// programmatically determined; states, properties, and values that can be
  /// set by the user can be programmatically set; and notification of changes
  /// to these items is available to user agents, including assistive
  /// technologies.
  static const wcag412 = WcagRef(
    number: '4.1.2',
    title: 'Name, Role, Value',
    url: 'https://www.w3.org/WAI/WCAG21/Understanding/name-role-value.html',
  );
}

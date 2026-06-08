/**
 * i18n utilities — pure module, no Astro runtime dependency.
 * Locales: 'en' (default, no URL prefix), 'de' (prefix /de/).
 */

export type Locale = 'en' | 'de';

const SITE = 'https://getloam.dev';
const LOCALES: Locale[] = ['en', 'de'];
const NON_DEFAULT_PREFIX = '/de';

/**
 * Derive the locale from a URL path.
 * /de/... → 'de'; everything else → 'en'.
 */
export function resolveLocale(path: string): Locale {
  if (path === '/de' || path === '/de/' || path.startsWith('/de/')) {
    return 'de';
  }
  return 'en';
}

/**
 * Return the counterpart URL for the given path in the target locale.
 * Preserves trailing slashes.
 *
 * /how-it-works       + 'de' → /de/how-it-works
 * /de/how-it-works    + 'en' → /how-it-works
 * /                   + 'de' → /de/
 * /de/                + 'en' → /
 */
export function counterpartUrl(path: string, targetLocale: Locale): string {
  const currentLocale = resolveLocale(path);

  // Nothing to do when we're already in the target locale.
  if (currentLocale === targetLocale) return path;

  if (targetLocale === 'de') {
    // EN → DE: prepend /de
    if (path === '/') return '/de/';
    return `${NON_DEFAULT_PREFIX}${path}`;
  } else {
    // DE → EN: strip /de prefix
    if (path === '/de' || path === '/de/') return '/';
    // Strip /de at the start; path starts with /de/
    return path.slice(NON_DEFAULT_PREFIX.length);
  }
}

/**
 * Build the hreflang alternates list for a given path.
 * Always returns 3 entries: en, de, and x-default (pointing to EN).
 * Input path may be in any locale — the function normalises to EN first.
 */
export function hreflangAlternates(
  path: string,
): Array<{ hreflang: string; href: string }> {
  // Normalise to EN path (x-default is always EN).
  const enPath = resolveLocale(path) === 'de' ? counterpartUrl(path, 'en') : path;
  const dePath = counterpartUrl(enPath, 'de');

  return [
    { hreflang: 'en', href: `${SITE}${enPath}` },
    { hreflang: 'de', href: `${SITE}${dePath}` },
    { hreflang: 'x-default', href: `${SITE}${enPath}` },
  ];
}

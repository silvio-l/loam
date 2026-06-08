/**
 * Chrome label dictionary per locale.
 * Keys: nav links, copy/share buttons, switcher, footer.
 */

import type { Locale } from './utils';

export const ui: Record<Locale, Record<string, string>> = {
  en: {
    'nav.home': 'Home',
    'nav.howItWorks': 'How it works',
    'nav.rules': 'Rules',
    'nav.docs': 'Docs',
    'cmd.copy': 'copy',
    'cmd.copied': 'copied',
    'cmd.share': 'share',
    'cmd.linkCopied': 'link copied',
    'switcher.label': 'DE',
    'switcher.ariaLabel': 'Switch to German',
    'footer.devGuide': 'Developer Guide',
    'footer.privacy': 'Privacy',
    'footer.copyright': '© 2026 Silvio Lindstedt · MIT · built in the open',
    'privacy.title': 'Privacy Policy — loam.dev',
    'privacy.heading': 'Privacy Policy',
    'stars.label': 'Star on GitHub',
    'stars.ariaLabel': 'Star loam.dev on GitHub',
  },
  de: {
    'nav.home': 'Start',
    'nav.howItWorks': 'Funktionsweise',
    'nav.rules': 'Rules',
    'nav.docs': 'Doku',
    'cmd.copy': 'kopieren',
    'cmd.copied': 'kopiert',
    'cmd.share': 'teilen',
    'cmd.linkCopied': 'Link kopiert',
    'switcher.label': 'EN',
    'switcher.ariaLabel': 'Zu Englisch wechseln',
    'footer.devGuide': 'Developer Guide',
    'footer.privacy': 'Datenschutz',
    'footer.copyright': '© 2026 Silvio Lindstedt · MIT · quelloffen gebaut',
    'privacy.title': 'Datenschutzerklärung — loam.dev',
    'privacy.heading': 'Datenschutzerklärung',
    'stars.label': 'Bei GitHub staren',
    'stars.ariaLabel': 'loam.dev auf GitHub staren',
  },
};

export function t(locale: Locale, key: string): string {
  return ui[locale][key] ?? ui['en'][key] ?? key;
}

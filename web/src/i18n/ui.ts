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
    'switcher.ariaLabel': 'DE — Switch to German',
    'footer.devGuide': 'Developer Guide',
    'footer.privacy': 'Privacy',
    'footer.copyright': '© 2026 Silvio Lindstedt · MIT · built in the open',
    'footer.author': 'silvio-lindstedt.de',
    'privacy.title': 'Privacy Policy — loam.dev',
    'privacy.heading': 'Privacy Policy',
    'stars.label': 'Star on GitHub',
    'stars.ariaLabel': 'Star on GitHub — loam.dev',
    'rules.badge.live': 'live',
    'rules.badge.planned': 'planned',
    'rules.slop.label': 'slop (bad)',
    'rules.clean.label': 'clean',
    'rules.deeper.heading': 'Going deeper',
    'rules.deeper.text': 'The',
    'rules.deeper.link': 'Developer Guide',
    'rules.deeper.suffix': 'covers the full CLI reference, configuration, and worked examples — including how to integrate',
    'rules.deeper.gate': 'loam gate',
    'rules.deeper.ci': 'into GitHub Actions.',
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
    'switcher.ariaLabel': 'EN — Zu Englisch wechseln',
    'footer.devGuide': 'Developer Guide',
    'footer.privacy': 'Datenschutz',
    'footer.copyright': '© 2026 Silvio Lindstedt · MIT · quelloffen gebaut',
    'footer.author': 'silvio-lindstedt.de',
    'privacy.title': 'Datenschutzerklärung — loam.dev',
    'privacy.heading': 'Datenschutzerklärung',
    'stars.label': 'Bei GitHub staren',
    'stars.ariaLabel': 'Bei GitHub staren — loam.dev',
    'rules.badge.live': 'live',
    'rules.badge.planned': 'geplant',
    'rules.slop.label': 'Slop (schlecht)',
    'rules.clean.label': 'sauber',
    'rules.deeper.heading': 'Mehr in die Tiefe',
    'rules.deeper.text': 'Der',
    'rules.deeper.link': 'Developer Guide',
    'rules.deeper.suffix': '(englisch) enthält die vollständige CLI-Referenz, Konfiguration und ausgearbeitete Beispiele — darunter die Integration von',
    'rules.deeper.gate': 'loam gate',
    'rules.deeper.ci': 'in GitHub Actions.',
  },
};

export function t(locale: Locale, key: string): string {
  return ui[locale][key] ?? ui['en'][key] ?? key;
}

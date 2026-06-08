// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// loam.dev Promo-/Doku-Website: reines Static-Site-Generation (kein Adapter,
// kein Server) für Free-Tier-Hosting (Cloudflare Pages / GitHub Pages).
// `output: 'static'` ist Astro-Default und hier bewusst explizit.
//
// @astrojs/sitemap ist als dokumentierte Ausnahme zur „keine Integrations"-
// Leitplanke erlaubt: der Sitemap-Generator ist deterministischer Build-Output
// (statisches XML), kein Runtime-Service, kein Server, kein Drittanbieter-Call.
export default defineConfig({
  site: 'https://getloam.dev',
  output: 'static',
  // Directory-Format-URLs enden auf einem Slash. Explizit gesetzt, damit die
  // canonical-/hreflang-Tags (Layout.astro) und die Sitemap-<loc>/<xhtml:link>-
  // Einträge exakt dieselbe URL-Form tragen (kein Trailing-Slash-Mismatch mehr).
  trailingSlash: 'always',
  integrations: [
    sitemap({
      i18n: {
        defaultLocale: 'en',
        locales: {
          en: 'en',
          de: 'de',
        },
      },
      // @astrojs/sitemap erzeugt en/de-hreflang-Alternates, aber kein x-default.
      // Das HTML rendert ein <link hreflang="x-default"> (EN) — hier in die
      // Sitemap gespiegelt, damit beide SEO-Signale übereinstimmen.
      /** @param {{ url: string; links?: Array<{ lang: string; url: string }> }} item */
      serialize(item) {
        if (item.links && item.links.length > 0) {
          const en = item.links.find((l) => l.lang === 'en');
          if (en && !item.links.some((l) => l.lang === 'x-default')) {
            item.links.push({ lang: 'x-default', url: en.url });
          }
        }
        return item;
      },
    }),
  ],
  i18n: {
    defaultLocale: 'en',
    locales: ['en', 'de'],
    routing: {
      prefixDefaultLocale: false,
    },
  },
});

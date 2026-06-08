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
  integrations: [
    sitemap({
      i18n: {
        defaultLocale: 'en',
        locales: {
          en: 'en',
          de: 'de',
        },
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

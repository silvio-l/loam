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

// Rehype-Plugin: der eingebettete Developer-Guide (docs/developer-guide.md) ist
// gegen seinen GitHub-Ort relativ verlinkt (z. B. ../README.md). On-Site würden
// solche Pfade brechen — hier auf absolute GitHub-Blob-URLs umgeschrieben.
// In-Page-Anker (#…), absolute (http/mailto) und Wurzel-Links (/…) bleiben.
function rehypeRewriteRelativeRepoLinks() {
  const GH = 'https://github.com/silvio-l/loam/blob/main/';
  /** @param {any} node */
  const walk = (node) => {
    if (
      node.type === 'element' &&
      node.tagName === 'a' &&
      node.properties &&
      typeof node.properties.href === 'string'
    ) {
      const href = node.properties.href;
      if (!/^(https?:|mailto:|#|\/)/.test(href)) {
        node.properties.href = GH + href.replace(/^(\.\.\/)+/, '');
      }
    }
    if (node.children) node.children.forEach(walk);
  };
  return (/** @type {any} */ tree) => walk(tree);
}

export default defineConfig({
  site: 'https://getloam.dev',
  output: 'static',
  markdown: {
    rehypePlugins: [rehypeRewriteRelativeRepoLinks],
  },
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

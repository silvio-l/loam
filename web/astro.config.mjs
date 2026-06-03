// @ts-check
import { defineConfig } from 'astro/config';

// loam.dev Promo-/Doku-Website: reines Static-Site-Generation (kein Adapter,
// kein Server) für Free-Tier-Hosting (Cloudflare Pages / GitHub Pages).
// `output: 'static'` ist Astro-Default und hier bewusst explizit.
export default defineConfig({
  site: 'https://getloam.dev',
  output: 'static',
});

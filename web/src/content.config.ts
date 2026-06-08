import { defineCollection } from 'astro:content';
import { glob } from 'astro/loaders';

// Single-Source: der „Developer & Tool Guide" lebt in /docs (eingecheckt) und
// wird als eigene On-Site-Seite gerendert. Der Content-Layer liest die Datei
// direkt aus ../docs — es gibt KEINE duplizierte Kopie unter web/. Damit bleibt
// docs/developer-guide.md die eine Quelle der Wahrheit (vgl. CONTEXT.md /
// public-docs-spec.md §6).
const guide = defineCollection({
  loader: glob({ pattern: 'developer-guide.md', base: '../docs' }),
});

export const collections = { guide };

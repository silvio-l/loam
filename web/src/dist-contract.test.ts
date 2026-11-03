/**
 * dist-contract.test.ts — handover contracts between the built HTML and
 * src/scripts/site.ts (no design, no wording):
 *   - every [data-copy-target] points at an element that exists on the same page,
 *   - pages using copy/share buttons carry the #status live region the script writes to,
 *   - every interactive element has a data-testid (project rule), ids are unique,
 *   - no inline event handlers (the hash-pinned CSP would block them).
 * Requires dist/ — run `npm run build` first.
 */
import { describe, it, expect } from "vitest";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { resolve, join } from "node:path";

const DIST = resolve(import.meta.dirname, "../dist");
if (!existsSync(DIST)) throw new Error("dist/ missing — run `npm run build` first");

const pages = readdirSync(DIST, { recursive: true })
  .map(String)
  .filter((f) => f.endsWith(".html") && f !== "demo-report.html" && !f.endsWith("/demo-report.html"))
  .map((f) => ({ name: f, html: readFileSync(join(DIST, f), "utf-8") }));

const attr = (tag: string, name: string) => tag.match(new RegExp(`\\s${name}="([^"]*)"`))?.[1];

describe("built pages honour the site.ts contracts", () => {
  it("builds pages to check", () => {
    expect(pages.length).toBeGreaterThan(0);
  });

  for (const { name, html } of pages) {
    describe(name, () => {
      it("copy targets exist and are non-empty", () => {
        for (const tag of html.match(/<button[^>]*\sdata-copy-target="[^"]*"[^>]*>/g) ?? []) {
          const target = attr(tag, "data-copy-target")!;
          const el = html.match(new RegExp(`<([a-z0-9]+)[^>]*\\sid="${target}"[^>]*>([\\s\\S]*?)</\\1>`));
          expect(el, `missing #${target}`).not.toBeNull();
          expect(el![2].replace(/<[^>]+>/g, "").trim(), `empty #${target}`).not.toBe("");
        }
      });

      it("has the #status live region when copy/share buttons exist", () => {
        if (/\sdata-copy-target="|\sdata-share="/.test(html)) {
          expect(html).toMatch(/\sid="status"/);
        }
      });

      it("every button has a data-testid", () => {
        for (const tag of html.match(/<button[^>]*>/g) ?? []) {
          expect(attr(tag, "data-testid"), tag).toBeTruthy();
        }
      });

      it("testids and ids are unique", () => {
        for (const a of ["data-testid", "id"]) {
          const values = [...html.matchAll(new RegExp(`<[a-z][^>]*\\s${a}="([^"]+)"`, "g"))].map((m) => m[1]);
          const dup = values.filter((v, i) => values.indexOf(v) !== i);
          expect(dup, a).toEqual([]);
        }
      });

      it("has no inline event handlers", () => {
        expect(html.match(/<[a-z][^>]*\son[a-z]+=/g) ?? []).toEqual([]);
      });
    });
  }
});

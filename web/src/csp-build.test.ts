/**
 * csp-build.test.ts — keeps the Content-Security-Policy in public/_headers in sync
 * with the built dist output (getloam.dev, Cloudflare Pages).
 *
 * A hash-pinned script-src only works if every executable inline script in the
 * built HTML is listed in the CSP. This test fails the build whenever:
 *   - an inline script appears in dist that the CSP does not hash-pin (would be
 *     blocked in production), or
 *   - the CSP carries a sha256 hash no dist script uses any more (stale → clean up).
 *
 * A <script> only runs as JS (and is only ever subject to script-src) when its
 * `type` attribute is absent, "", "text/javascript", "application/javascript", or
 * "module" — the HTML spec treats every other type (application/json,
 * application/ld+json, custom types like the report's text/x-loam-template) as an
 * inert data block the browser never executes, CSP or not. The demo report embeds
 * several such data blocks (findings JSON, a prompt template) whose content — and
 * therefore hash — legitimately changes on every `gen-demo-report.sh` regeneration;
 * treating them as data (matching browser behaviour) instead of chasing their hash
 * is what keeps this test from going stale on every report refresh.
 *
 * Requires dist/ — run `npm run build` first (CI builds before testing).
 */
import { describe, it, expect, beforeAll } from "vitest";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { resolve, join } from "node:path";
import { createHash } from "node:crypto";

const DIST = resolve(import.meta.dirname, "../dist");
const HEADERS = resolve(import.meta.dirname, "../public/_headers");

const JS_SCRIPT_TYPES = new Set(["", "text/javascript", "application/javascript", "module"]);

function distHtmlFiles(): string[] {
  if (!existsSync(DIST)) throw new Error("dist/ missing — run `npm run build` first");
  return readdirSync(DIST, { recursive: true })
    .map(String)
    .filter((f) => f.endsWith(".html"))
    .map((f) => join(DIST, f));
}

function execInlineHashes(): Set<string> {
  const hashes = new Set<string>();
  const re = /<script([^>]*)>([\s\S]*?)<\/script>/g;
  for (const f of distHtmlFiles()) {
    const html = readFileSync(f, "utf-8");
    let m: RegExpExecArray | null;
    while ((m = re.exec(html))) {
      const [, attrs, body] = m;
      if (/\bsrc=/.test(attrs)) continue; // external script → 'self'/host, no hash
      const typeMatch = attrs.match(/\btype\s*=\s*["']([^"']*)["']/i);
      const type = (typeMatch ? typeMatch[1] : "").toLowerCase();
      if (!JS_SCRIPT_TYPES.has(type)) continue; // non-JS type → inert data, CSP-exempt
      if (body.trim() === "") continue;
      hashes.add(createHash("sha256").update(body, "utf8").digest("base64"));
    }
  }
  return hashes;
}

function cspHashes(): Set<string> {
  const txt = readFileSync(HEADERS, "utf-8");
  return new Set([...txt.matchAll(/'sha256-([A-Za-z0-9+/=]+)'/g)].map((m) => m[1]));
}

describe("CSP hash pinning matches the built dist (loam)", () => {
  let inDist: Set<string>;
  let inCsp: Set<string>;
  beforeAll(() => {
    inDist = execInlineHashes();
    inCsp = cspHashes();
  });

  it("every executable inline script in dist is hash-pinned in the CSP", () => {
    expect([...inDist].filter((h) => !inCsp.has(h))).toEqual([]);
  });

  it("no stale CSP hash that the dist no longer uses", () => {
    expect([...inCsp].filter((h) => !inDist.has(h))).toEqual([]);
  });

  it("locks down the dangerous directives", () => {
    const csp = readFileSync(HEADERS, "utf-8");
    for (const d of [
      "default-src 'self'",
      "object-src 'none'",
      "base-uri 'self'",
      "frame-ancestors 'none'",
    ]) {
      expect(csp).toContain(d);
    }
  });

  it("allows the Matomo endpoint for script + connect", () => {
    const csp = readFileSync(HEADERS, "utf-8");
    expect(csp).toContain("script-src 'self' https://matomo.silvio-und-maik.de");
    expect(csp).toContain("connect-src 'self' https://matomo.silvio-und-maik.de");
  });
});

// Regression guard for the black-iframe bug (2026-08-08): a _headers rule keyed to
// /demo-report.html never applies, because Cloudflare Pages' Clean URLs feature
// 308-redirects that path to the extensionless /demo-report before the browser ever
// sees a body — so the site-wide X-Frame-Options: DENY / frame-ancestors 'none'
// silently governed the framed document instead of the intended per-route override.
describe("demo-report iframe embedding survives Clean URLs (loam)", () => {
  const headersTxt = readFileSync(HEADERS, "utf-8");
  const demoReportAstro = readFileSync(
    resolve(import.meta.dirname, "components/DemoReport.astro"),
    "utf-8",
  );

  it("has no _headers rule keyed to the redirected .html path", () => {
    expect(headersTxt).not.toMatch(/^\/demo-report\.html$/m);
  });

  it("has a _headers rule keyed to the canonical extensionless path that detaches and relaxes framing", () => {
    const start = headersTxt.indexOf("\n/demo-report\n") + 1;
    expect(start).toBeGreaterThan(0);
    const nextRule = headersTxt.indexOf("\n/", start + "/demo-report\n".length);
    const block = nextRule === -1 ? headersTxt.slice(start) : headersTxt.slice(start, nextRule);
    expect(block).toContain("! X-Frame-Options");
    expect(block).toContain("X-Frame-Options: SAMEORIGIN");
    expect(block).toContain("frame-ancestors 'self'");
  });

  it("DemoReport.astro's iframe src and full-screen link both point at the extensionless path the _headers rule covers", () => {
    expect(demoReportAstro).toMatch(/src="\/demo-report"/);
    expect(demoReportAstro).toMatch(/href="\/demo-report"/);
    expect(demoReportAstro).not.toMatch(/(?:src|href)="\/demo-report\.html"/);
  });
});

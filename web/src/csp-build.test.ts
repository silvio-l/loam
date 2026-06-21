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
 * JSON-LD (<script type="application/ld+json">) is data, not executed, and is not
 * subject to script-src — it is intentionally excluded.
 *
 * Requires dist/ — run `npm run build` first (CI builds before testing).
 */
import { describe, it, expect, beforeAll } from "vitest";
import { readFileSync, readdirSync, existsSync } from "node:fs";
import { resolve, join } from "node:path";
import { createHash } from "node:crypto";

const DIST = resolve(import.meta.dirname, "../dist");
const HEADERS = resolve(import.meta.dirname, "../public/_headers");

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
      if (/application\/ld\+json/.test(attrs)) continue; // data, CSP-exempt
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

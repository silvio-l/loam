import { describe, it, expect } from 'vitest';
import { resolveLocale, counterpartUrl, hreflangAlternates } from './utils';

describe('resolveLocale', () => {
  it('returns "de" for /de/rules', () => {
    expect(resolveLocale('/de/rules')).toBe('de');
  });

  it('returns "en" for /rules (no prefix)', () => {
    expect(resolveLocale('/rules')).toBe('en');
  });

  it('returns "en" for root /', () => {
    expect(resolveLocale('/')).toBe('en');
  });

  it('returns "de" for /de/ (DE root)', () => {
    expect(resolveLocale('/de/')).toBe('de');
  });

  it('returns "de" for /de (DE root without trailing slash)', () => {
    expect(resolveLocale('/de')).toBe('de');
  });

  it('returns "en" for /how-it-works', () => {
    expect(resolveLocale('/how-it-works')).toBe('en');
  });

  it('returns "de" for /de/how-it-works', () => {
    expect(resolveLocale('/de/how-it-works')).toBe('de');
  });
});

describe('counterpartUrl', () => {
  it('maps /how-it-works → /de/how-it-works when targeting de', () => {
    expect(counterpartUrl('/how-it-works', 'de')).toBe('/de/how-it-works');
  });

  it('maps /de/how-it-works → /how-it-works when targeting en', () => {
    expect(counterpartUrl('/de/how-it-works', 'en')).toBe('/how-it-works');
  });

  it('maps root / → /de/ when targeting de', () => {
    expect(counterpartUrl('/', 'de')).toBe('/de/');
  });

  it('maps /de/ → / when targeting en', () => {
    expect(counterpartUrl('/de/', 'en')).toBe('/');
  });

  it('maps /de → / when targeting en (no trailing slash)', () => {
    expect(counterpartUrl('/de', 'en')).toBe('/');
  });

  it('maps /rules with trailing slash → /de/rules/ when targeting de', () => {
    expect(counterpartUrl('/rules/', 'de')).toBe('/de/rules/');
  });

  it('maps /de/rules/ → /rules/ when targeting en', () => {
    expect(counterpartUrl('/de/rules/', 'en')).toBe('/rules/');
  });

  it('returns same EN path when already en', () => {
    expect(counterpartUrl('/rules', 'en')).toBe('/rules');
  });

  it('returns same DE path when already de', () => {
    expect(counterpartUrl('/de/rules', 'de')).toBe('/de/rules');
  });
});

describe('hreflangAlternates', () => {
  it('returns both language URLs + x-default for /rules', () => {
    const alts = hreflangAlternates('/rules');
    expect(alts).toContainEqual({ hreflang: 'en', href: 'https://getloam.dev/rules' });
    expect(alts).toContainEqual({ hreflang: 'de', href: 'https://getloam.dev/de/rules' });
    expect(alts).toContainEqual({ hreflang: 'x-default', href: 'https://getloam.dev/rules' });
  });

  it('works for root / (EN home)', () => {
    const alts = hreflangAlternates('/');
    expect(alts).toContainEqual({ hreflang: 'en', href: 'https://getloam.dev/' });
    expect(alts).toContainEqual({ hreflang: 'de', href: 'https://getloam.dev/de/' });
    expect(alts).toContainEqual({ hreflang: 'x-default', href: 'https://getloam.dev/' });
  });

  it('works for /de/rules (DE path)', () => {
    const alts = hreflangAlternates('/de/rules');
    expect(alts).toContainEqual({ hreflang: 'en', href: 'https://getloam.dev/rules' });
    expect(alts).toContainEqual({ hreflang: 'de', href: 'https://getloam.dev/de/rules' });
    expect(alts).toContainEqual({ hreflang: 'x-default', href: 'https://getloam.dev/rules' });
  });

  it('x-default always points to EN URL', () => {
    const alts = hreflangAlternates('/de/how-it-works');
    const xdef = alts.find(a => a.hreflang === 'x-default');
    expect(xdef?.href).toBe('https://getloam.dev/how-it-works');
  });

  it('has exactly 3 entries (en + de + x-default)', () => {
    expect(hreflangAlternates('/rules')).toHaveLength(3);
  });
});

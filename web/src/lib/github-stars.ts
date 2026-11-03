// Build-time star count for the header badge. Fetched once per build and
// shared by every page; any failure (network, timeout, rate limit) yields
// null so the badge renders without a number and the build never fails.
let pending: Promise<number | null> | undefined;

export function githubStars(): Promise<number | null> {
  pending ??= (async () => {
    try {
      const controller = new AbortController();
      const timer = setTimeout(() => controller.abort(), 3000);
      const res = await fetch('https://api.github.com/repos/silvio-l/loam', {
        signal: controller.signal,
        headers: { Accept: 'application/vnd.github+json' },
      });
      clearTimeout(timer);
      if (!res.ok) return null;
      const data = await res.json();
      return typeof data.stargazers_count === 'number' ? data.stargazers_count : null;
    } catch {
      return null;
    }
  })();
  return pending;
}

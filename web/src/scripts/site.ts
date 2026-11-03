// Site behaviour for getloam.dev — bundled by Astro into one first-party module
// served from 'self' (no inline JS, so the hash-pinned CSP needs no new entry).
// Everything here is progressive enhancement: the pages are fully readable and
// the install commands selectable without JS.

type Paq = unknown[][];
const paq = (): Paq => ((window as unknown as { _paq?: Paq })._paq ??= []);

// One polite live region per page for copy/share feedback.
const status = document.getElementById('status');
let sayTimer: number | undefined;
function say(message: string): void {
  if (!status) return;
  window.clearTimeout(sayTimer);
  status.textContent = '';
  sayTimer = window.setTimeout(() => {
    status.textContent = message;
    sayTimer = window.setTimeout(() => (status.textContent = ''), 4000);
  }, 50);
}

function flash(button: HTMLElement, label: string): void {
  const original = button.dataset.label ?? button.textContent ?? '';
  button.dataset.label = original;
  button.textContent = label;
  button.classList.add('ok');
  window.setTimeout(() => {
    button.textContent = original;
    button.classList.remove('ok');
  }, 1600);
}

// Copy buttons: <button data-copy-target="id-of-element-with-the-command">.
document.querySelectorAll<HTMLButtonElement>('[data-copy-target]').forEach((button) => {
  button.addEventListener('click', async () => {
    const target = document.getElementById(button.dataset.copyTarget ?? '');
    const text = target?.textContent?.trim();
    if (!text) return;
    try {
      await navigator.clipboard.writeText(text);
      const done = button.dataset.done ?? 'copied';
      flash(button, done);
      say(done);
      paq().push(['trackEvent', 'Engagement', 'Install kopiert', button.dataset.track ?? 'Install']);
    } catch {
      say(button.dataset.failed ?? 'copy failed');
    }
  });
});

// Share: native share sheet where available, otherwise copy the URL.
document.querySelectorAll<HTMLButtonElement>('[data-share]').forEach((button) => {
  button.addEventListener('click', async () => {
    const shareData = {
      title: 'loam.dev',
      text: button.dataset.shareText ?? 'loam.dev',
      url: button.dataset.share ?? 'https://getloam.dev/',
    };
    try {
      if (navigator.share) {
        await navigator.share(shareData);
        return;
      }
      await navigator.clipboard.writeText(shareData.url);
      const done = button.dataset.done ?? 'link copied';
      flash(button, done);
      say(done);
    } catch (error) {
      if (!(error instanceof DOMException && error.name === 'AbortError')) say(button.dataset.failed ?? 'copy failed');
    }
  });
});

// Demo-report links outside the DemoReport component (which tracks its own).
document.querySelectorAll<HTMLAnchorElement>('a[data-track="report"]').forEach((link) => {
  link.addEventListener('click', () => paq().push(['trackEvent', 'Engagement', 'Demo-Report geöffnet', 'report']));
});

// Report preview: render the real report at a fixed desktop width and scale it
// down to the frame, so every screen sees the same two-column report layout.
document.querySelectorAll<HTMLElement>('[data-report-scale]').forEach((viewport) => {
  const frame = viewport.querySelector('iframe');
  const base = Number(viewport.dataset.reportScale) || 1200;
  if (!frame || !('ResizeObserver' in window)) return;
  const fit = (): void => {
    const scale = viewport.clientWidth / base;
    viewport.style.setProperty('--rp-scale', String(scale));
    viewport.style.setProperty('--rp-base', `${base}px`);
    viewport.classList.add('is-scaled');
  };
  new ResizeObserver(fit).observe(viewport);
  fit();
});

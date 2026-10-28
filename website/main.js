import { createAmbientArtwork } from './artwork.js';
const releasePage = 'https://github.com/Caldis/Pir/releases/latest';
createAmbientArtwork();

async function resolveDownload() {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 4500);
  try {
    const response = await fetch('https://api.github.com/repos/Caldis/Pir/releases/latest', { headers: { Accept: 'application/vnd.github+json' }, signal: controller.signal });
    if (!response.ok) return;
    const release = await response.json();
    const asset = release.assets?.find((item) => /\.dmg$/i.test(item.name));
    // Release API data is external input; only official GitHub release assets qualify.
    const download = asset?.browser_download_url;
    const trusted = typeof download === 'string' && download.startsWith('https://github.com/Caldis/Pir/releases/download/');
    for (const link of document.querySelectorAll('[data-download]')) link.href = trusted ? download : releasePage;
    if (typeof release.tag_name === 'string' && /^v?\d[\w.-]{0,30}$/.test(release.tag_name)) {
      document.querySelector('[data-release-note]').firstChild.textContent = `${release.tag_name} · macOS 13+ `;
    }
  } catch {
    // Static release links also work when GitHub's public API is unavailable.
  } finally {
    clearTimeout(timeout);
  }
}
resolveDownload();

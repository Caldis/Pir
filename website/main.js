import { createAmbientArtwork } from './artwork.js';
const releasePage = 'https://github.com/Caldis/Pir/releases/latest';
const artwork = createAmbientArtwork();

for (const panel of document.querySelectorAll('[data-draggable]')) {
  let offset = { x: 0, y: 0 };
  let origin;
  const rotation = 0;
  const paintPosition = () => { panel.style.transform = `translate(${offset.x}px, ${offset.y}px) rotate(${rotation}deg)`; };
  panel.addEventListener('pointerdown', (event) => {
    if (event.target.closest('button')) return;
    const bounds = panel.getBoundingClientRect();
    // Leave the native bottom-right resize affordance available.
    if (event.clientX > bounds.right - 28 && event.clientY > bounds.bottom - 28) return;
    origin = { x: event.clientX - offset.x, y: event.clientY - offset.y };
    panel.setPointerCapture(event.pointerId);
    panel.classList.add('is-dragging');
  });
  panel.addEventListener('pointermove', (event) => {
    if (!origin) return;
    const sceneBounds = panel.parentElement.getBoundingClientRect();
    offset = { x: Math.max(-sceneBounds.width * .35, Math.min(sceneBounds.width * .35, event.clientX - origin.x)), y: Math.max(-150, Math.min(100, event.clientY - origin.y)) };
    paintPosition();
  });
  const stop = () => { origin = null; panel.classList.remove('is-dragging'); };
  panel.addEventListener('pointerup', stop);
  panel.addEventListener('pointercancel', stop);
  panel.addEventListener('lostpointercapture', stop);
  panel.addEventListener('keydown', (event) => {
    const directions = { ArrowLeft: [-10, 0], ArrowRight: [10, 0], ArrowUp: [0, -10], ArrowDown: [0, 10] };
    if (event.target !== panel || !directions[event.key]) return;
    event.preventDefault();
    const [x, y] = directions[event.key];
    offset.x = Math.max(-150, Math.min(150, offset.x + x));
    offset.y = Math.max(-150, Math.min(100, offset.y + y));
    paintPosition();
  });
  panel.resetDemo = () => { offset = { x: 0, y: 0 }; panel.hidden = false; panel.style.width = ''; panel.style.height = ''; paintPosition(); };
}
for (const button of document.querySelectorAll('[data-close]')) {
  button.addEventListener('click', () => {
    document.querySelector(`.${button.dataset.close}`).hidden = true;
    document.querySelector('#reset-demo').focus();
    artwork.update();
  });
}
document.querySelector('#reset-demo').addEventListener('click', () => {
  document.querySelectorAll('[data-draggable]').forEach((panel) => panel.resetDemo());
  artwork.update();
});

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

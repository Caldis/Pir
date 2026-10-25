const releasePage = 'https://github.com/Caldis/Puv/releases/latest';
const motionPreference = matchMedia('(prefers-reduced-motion: reduce)');
const canvas = document.querySelector('#shader-art');
const artPanel = document.querySelector('.scene-glow');
let shader;
let shaderLoading = false;
let visible = true;
let pausedByUser = false;
let destroyed = false;

// The CSS artwork remains visible when WebGPU is absent or the GPU is lost.
async function startArtwork() {
  if (shader || shaderLoading || destroyed || motionPreference.matches || navigator.connection?.saveData || !navigator.gpu) return;
  shaderLoading = true;
  try {
    const { createShader } = await import('shaders/js');
    if (destroyed) return;
    shader = await createShader(canvas, {
      components: [{ type: 'Aurora', id: 'light', props: {
        colorA: '#b591ed', colorB: '#a9ece5', colorC: '#eea7a6',
        intensity: 67, speed: 0.12, curtainCount: 3, waviness: 60,
        rayDensity: 32, height: 65, center: { x: 0.49, y: 0.6 }, seed: 14,
      } }],
    }, {
      disableTelemetry: true,
      observeElement: false,
      onReady: () => artPanel.classList.add('shader-ready'),
      onError: () => artPanel.classList.remove('shader-ready'),
    });
    if (destroyed) { shader.destroy(); return; }
    resizeArtwork();
    updatePlayback();
  } catch {
    artPanel.classList.remove('shader-ready');
  } finally {
    shaderLoading = false;
  }
}

function resizeArtwork() {
  if (!shader) return;
  // A 520px render target keeps the decorative shader's pixel cost bounded.
  const bounds = canvas.getBoundingClientRect();
  const scale = Math.min(1, 520 / Math.max(bounds.width, bounds.height));
  shader.resize(Math.max(1, Math.round(bounds.width * scale)), Math.max(1, Math.round(bounds.height * scale)));
  canvas.style.width = '100%';
  canvas.style.height = '100%';
}

function updatePlayback() {
  const shouldPause = document.hidden || !visible || pausedByUser || motionPreference.matches;
  if (shader) shader[shouldPause ? 'pause' : 'resume']();
  const button = document.querySelector('#motion-toggle');
  button.setAttribute('aria-pressed', String(pausedByUser));
  button.setAttribute('aria-label', pausedByUser ? '播放动态效果' : '暂停动态效果');
  button.innerHTML = pausedByUser
    ? '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="m5 3 7 5-7 5Z"/></svg>'
    : '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M5 3v10M11 3v10"/></svg>';
}

const visibilityObserver = new IntersectionObserver(([entry]) => {
  visible = entry.isIntersecting;
  if (visible) startArtwork();
  updatePlayback();
}, { threshold: 0.01 });
visibilityObserver.observe(artPanel);
const resizeObserver = new ResizeObserver(resizeArtwork);
resizeObserver.observe(artPanel);
document.addEventListener('visibilitychange', updatePlayback);
motionPreference.addEventListener('change', () => { startArtwork(); updatePlayback(); });
document.querySelector('#motion-toggle').addEventListener('click', () => {
  pausedByUser = !pausedByUser;
  startArtwork();
  updatePlayback();
});

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
    updatePlayback();
  });
}
document.querySelector('#reset-demo').addEventListener('click', () => {
  document.querySelectorAll('[data-draggable]').forEach((panel) => panel.resetDemo());
  updatePlayback();
});

async function resolveDownload() {
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 4500);
  try {
    const response = await fetch('https://api.github.com/repos/Caldis/Puv/releases/latest', { headers: { Accept: 'application/vnd.github+json' }, signal: controller.signal });
    if (!response.ok) return;
    const release = await response.json();
    const asset = release.assets?.find((item) => /\.dmg$/i.test(item.name));
    // Release API data is external input; only official GitHub release assets qualify.
    const download = asset?.browser_download_url;
    const trusted = typeof download === 'string' && download.startsWith('https://github.com/Caldis/Puv/releases/download/');
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
window.addEventListener('pagehide', (event) => {
  if (event.persisted) { shader?.pause(); return; }
  destroyed = true;
  shader?.destroy();
  resizeObserver.disconnect();
  visibilityObserver.disconnect();
});
window.addEventListener('pageshow', (event) => { if (event.persisted) updatePlayback(); });

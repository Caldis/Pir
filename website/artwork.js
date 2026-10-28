import { t } from './i18n.js';
// One canvas supplies ambient light behind the native product screenshots.
export function createAmbientArtwork() {
  const panel = document.querySelector('.ambient-art');
  const canvas = panel.querySelector('canvas');
  const button = document.querySelector('#motion-toggle');
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const connection = navigator.connection;
  let shader;
  let loading = false;
  let failed = false;
  let visible = false;
  let paused = false;
  let suspended = false;
  let disposed = false;

  const canPlay = () => !disposed && !suspended && !document.hidden && visible && !paused && !motion.matches && !connection?.saveData;

  function resize() {
    if (!shader || disposed) return;
    const { width, height } = panel.getBoundingClientRect();
    // Reserve a 2x DPR budget, including monitor changes while this renderer is alive.
    const limit = width < 760 ? 640 : 1100;
    const scale = Math.min(1, limit / (Math.max(width, height) * Math.max(2, devicePixelRatio)));
    shader.resize(Math.max(1, Math.round(width * scale)), Math.max(1, Math.round(height * scale)));
    canvas.style.width = '100%';
    canvas.style.height = '100%';
  }

  async function start() {
    if (shader || loading || failed || !canPlay() || !navigator.gpu) return;
    loading = true;
    try {
      const { createShader } = await import('shaders/js');
      if (!canPlay()) return;
      shader = await createShader(canvas, {
        components: [
          { type: 'Swirl', id: 'fluid', props: {
            stops: [
              { color: '#080b19', position: 0 },
              { color: '#293ba1', position: .24 },
              { color: '#a8a2f5', position: .45 },
              { color: '#75d9e2', position: .58 },
              { color: '#43338c', position: .73 },
              { color: '#e2a4b3', position: .88 },
              { color: '#131227', position: 1 },
            ], speed: .13, detail: 1.35, blend: 48, colorSpace: 'oklch',
          } },
          { type: 'FlutedGlass', id: 'refraction', props: {
            shape: 'waves', angle: -32, frequency: 3.2, softness: .8,
            waveAmplitude: .15, waveFrequency: 1.1, speed: .035,
            refraction: .65, aberration: .12, highlight: .16,
            highlightSoftness: .65, highlightColor: '#c7e9ff', edges: 'mirror',
          } },
          { type: 'FilmGrain', id: 'grain', props: { strength: .075, bias: 1.1, animated: false } },
        ],
      }, {
        disableTelemetry: true,
        observeElement: false,
        onReady: () => {
          if (disposed) return;
          panel.classList.add('shader-ready');
          // Device recovery creates a new renderer with its own size and playback state.
          resize();
          update();
        },
        onError: () => {
          panel.classList.remove('shader-ready');
          failed = Boolean(shader?.getFailureReason());
          update();
        },
      });
      if (disposed) { shader.destroy(); return; }
      failed = Boolean(shader.getFailureReason());
      resize();
      update();
    } catch {
      failed = true;
      panel.classList.remove('shader-ready');
    } finally {
      loading = false;
      if (failed) update();
    }
  }

  function update() {
    if (disposed) return;
    shader?.[canPlay() ? 'resume' : 'pause']();
    const staticMode = motion.matches || Boolean(connection?.saveData) || !navigator.gpu || failed;
    panel.classList.toggle('static-art', staticMode);
    button.disabled = staticMode;
    button.setAttribute('aria-pressed', String(paused));
    button.setAttribute('aria-label', t(staticMode ? 'motion.static' : paused ? 'motion.play' : 'motion.pause'));
    button.innerHTML = paused
      ? '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="m5 3 7 5-7 5Z"/></svg>'
      : '<svg viewBox="0 0 16 16" aria-hidden="true"><path d="M5 3v10M11 3v10"/></svg>';
    start();
  }

  const visibility = new IntersectionObserver(([entry]) => {
    visible = entry.isIntersecting;
    update();
  }, { threshold: .01 });
  visibility.observe(panel);
  const size = new ResizeObserver(resize);
  size.observe(panel);
  document.addEventListener('visibilitychange', update);
  document.addEventListener('pir-languagechange', update);
  motion.addEventListener('change', update);
  connection?.addEventListener('change', update);
  button.addEventListener('click', () => { paused = !paused; update(); });
  window.addEventListener('pagehide', (event) => {
    suspended = true;
    shader?.pause();
    if (event.persisted) return;
    disposed = true;
    shader?.destroy();
    visibility.disconnect();
    size.disconnect();
    document.removeEventListener('visibilitychange', update);
    motion.removeEventListener('change', update);
    connection?.removeEventListener('change', update);
  });
  window.addEventListener('pageshow', () => { suspended = false; update(); });
  update();
  return { update };
}

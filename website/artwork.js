// One canvas supplies ambient light behind the interactive windows.
export function createAmbientArtwork() {
  const panel = document.querySelector('.ambient-art');
  const canvas = panel.querySelector('canvas');
  const motion = matchMedia('(prefers-reduced-motion: reduce)');
  const connection = navigator.connection;
  let shader;
  let loading = false;
  let failed = false;
  let visible = false;
  let suspended = false;
  let disposed = false;

  const canPlay = () => !disposed && !suspended && !document.hidden && visible && !motion.matches && !connection?.saveData;

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
          { type: 'MeshGradient', id: 'light', props: {
            stops: [
              { color: '#0c1420', position: 0 },
              { color: '#42616d', position: .32 },
              { color: '#8b9fb1', position: .56 },
              { color: '#807799', position: .78 },
              { color: '#141525', position: 1 },
            ], count: 5, smoothness: 2.8, variation: .18,
            swirl: .08, drift: .22, wrapping: 0, speed: .12,
            seed: 14, colorSpace: 'oklab',
          } },
          { type: 'FilmGrain', id: 'grain', props: { strength: .035, bias: 1.1, animated: false } },
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
  window.addEventListener('pagehide', (event) => {
    suspended = true;
    shader?.pause();
    if (event.persisted) return;
    disposed = true;
    shader?.destroy();
    visibility.disconnect();
    size.disconnect();
    document.removeEventListener('visibilitychange', update);
    document.removeEventListener('pir-languagechange', update);
    motion.removeEventListener('change', update);
    connection?.removeEventListener('change', update);
  });
  window.addEventListener('pageshow', () => { suspended = false; update(); });
  update();
  return { update };
}

// Dust in the light that falls from the notch: specks drift everywhere, and show where the beam is.

const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');
const SPECKS = 90;
/** The beam, as the hero draws it: how tall it is, and half its width at the top and at the bottom. */
const BEAM = { height: 0.58, top: 0.012, bottom: 0.16 };

interface Speck { x: number; y: number; depth: number; drift: number; phase: number }

export function startDust(canvas: HTMLCanvasElement) {
  const ctx = canvas.getContext('2d')!;
  const specks: Speck[] = Array.from({ length: SPECKS }, () => ({
    // Most of them near the middle, where the light is.
    x: 0.5 + (Math.random() + Math.random() - 1) * 0.42, y: Math.random(),
    depth: 0.3 + Math.random() * 0.7, drift: 0.004 + Math.random() * 0.012, phase: Math.random() * 6.28,
  }));
  let width = 0, height = 0, visible = true;

  const resize = () => {
    const ratio = Math.min(2, window.devicePixelRatio || 1);
    // The toolbars of a mobile browser resize the window all the time; the canvas rarely changes.
    if (canvas.clientWidth === width && canvas.clientHeight === height) return;
    width = canvas.clientWidth;
    height = canvas.clientHeight;
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    paint(0);
  };

  /** How much of the beam's light reaches this point: 1 on its axis, 0 well outside it. */
  const light = (x: number, y: number) => {
    if (y > BEAM.height) return Math.max(0, 1 - (y - BEAM.height) * 9) * 0.5;
    const half = BEAM.top + (BEAM.bottom - BEAM.top) * (y / BEAM.height);
    return Math.max(0, 1 - Math.abs(x - 0.5) / half);
  };

  function paint(t: number) {
    ctx.clearRect(0, 0, width, height);
    for (const speck of specks) {
      const y = (speck.y - t * speck.drift + 10) % 1;
      const x = speck.x + Math.sin(t * 0.25 + speck.phase) * 0.012;
      const lit = light(x, y);
      ctx.globalAlpha = (0.05 + lit * 0.75) * speck.depth;
      ctx.fillStyle = '#ffe9c4';
      ctx.beginPath();
      ctx.arc(x * width, y * height, 0.5 + speck.depth * 1.1, 0, 6.3);
      ctx.fill();
    }
  }

  new IntersectionObserver(([entry]) => { visible = entry.isIntersecting; }).observe(canvas);
  addEventListener('resize', resize);
  resize();
  const frame = (now: number) => {
    if (visible && !reducedMotion.matches) paint(now / 1000);
    requestAnimationFrame(frame);
  };
  requestAnimationFrame(frame);
}

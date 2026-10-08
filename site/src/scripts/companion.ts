// The companion: a port of Sources/NotchApp/Companion.swift to a canvas.
import type { Counters } from '../lib/demo';

export type Mood = 'asleep' | 'working' | 'waiting' | 'finished' | 'failed';

/** One mood for all sessions: the one that matters most wins. */
export function moodOf(counters: Counters): Mood {
  if (counters.waiting) return 'waiting';
  if (counters.failed) return 'failed';
  if (counters.working) return 'working';
  if (counters.finished) return 'finished';
  return 'asleep';
}

export const MOOD_LABEL: Record<Mood, string> = {
  asleep: 'No live sessions',
  working: 'Sessions are working',
  waiting: 'A session waits for you',
  finished: 'Sessions have finished',
  failed: 'A session failed',
};

const SKIN = '#e07a52', SKIN_SHADE = '#c9643f', EYE = '#1b1410', LAPTOP = '#4a4a4a', SCREEN = '#9cc4e8', SWEAT = '#7fb3e6';
const DEG = Math.PI / 180;
/** The frame a companion rests on when the visitor asked for no motion. */
const STILL = 0.4;

const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');

type Eyes = 'wide' | 'closed' | 'down' | 'low' | 'happy';

/** One frame of the companion at time `t`, in a box `s` pixels tall, around the canvas centre. */
function draw(ctx: CanvasRenderingContext2D, mood: Mood, t: number, s: number, width: number, height: number) {
  const bodyWidth = 0.74 * s, bodyHeight = 0.56 * s, leg = 0.1 * s, corner = 0.17 * s;
  const phase = (period: number, offset = 0) => ((t + offset) / period) % 1;
  const wave = (period: number, offset = 0) => Math.sin((t / period + offset) * 2 * Math.PI);
  const block = (x: number, y: number, w: number, h: number, r: number, color: string) => {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.roundRect(x, y, w, h, r);
    ctx.fill();
  };

  const legs = () => {
    for (const side of [-1, 1]) block(side * 0.2 * s - 0.065 * s, -leg - 0.02 * s, 0.13 * s, leg + 0.02 * s, 0.04 * s, SKIN_SHADE);
  };
  const arm = (side: number, degrees: number) => {
    ctx.save();
    ctx.translate(side * (bodyWidth / 2 - 0.02 * s), -leg - bodyHeight + 0.26 * bodyHeight);
    ctx.rotate(degrees * DEG);
    block(-0.055 * s, -0.02 * s, 0.11 * s, 0.26 * s, 0.055 * s, SKIN_SHADE);
    ctx.restore();
  };
  /** The body, with its arms at these angles; without angles the hands are busy elsewhere. */
  const body = (arms?: [left: number, right: number]) => {
    if (arms) { arm(-1, arms[0]); arm(1, arms[1]); }
    block(-bodyWidth / 2, -leg - bodyHeight, bodyWidth, bodyHeight, corner, SKIN);
  };
  const eyes = (kind: Eyes) => {
    const centreY = -leg - bodyHeight + 0.4 * bodyHeight;
    ctx.strokeStyle = EYE;
    ctx.lineCap = 'round';
    for (const side of [-1, 1]) {
      const x = side * 0.17 * s;
      if (kind === 'closed') {
        ctx.lineWidth = 0.045 * s;
        ctx.beginPath();
        ctx.moveTo(x - 0.06 * s, centreY + 0.02 * s);
        ctx.lineTo(x + 0.06 * s, centreY + 0.02 * s);
        ctx.stroke();
      } else if (kind === 'happy') {
        ctx.lineWidth = 0.05 * s;
        ctx.beginPath();
        ctx.arc(x, centreY + 0.03 * s, 0.07 * s, 200 * DEG, 340 * DEG);
        ctx.stroke();
      } else {
        const h = { wide: 0.24, low: 0.1, down: 0.16 }[kind] * s;
        const drop = { wide: 0, low: 0.05, down: 0.02 }[kind] * s;
        block(x - 0.045 * s, centreY - h / 2 + drop, 0.09 * s, h, 0.045 * s, EYE);
      }
    }
  };

  ctx.clearRect(0, 0, width, height);
  ctx.save();
  // Everything is drawn around the point where the feet meet the ground.
  ctx.translate(width / 2, height / 2 + 0.36 * s);

  if (mood === 'asleep') {
    // Slow breathing, and two z's that float up one after the other.
    const breath = 1 + 0.035 * wave(2.8);
    ctx.save();
    ctx.scale(1 / Math.sqrt(breath), breath);
    legs(); body([12, -12]); eyes('closed');
    ctx.restore();
    ctx.font = `bold ${0.3 * s}px -apple-system, system-ui, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.fillStyle = SKIN;
    for (const offset of [0, 1.1]) {
      const p = phase(2.2, offset), rise = p * 0.28 * s;
      ctx.globalAlpha = p < 0.15 ? p / 0.15 : 1 - (p - 0.15) / 0.85;
      ctx.fillText('z', bodyWidth / 2 + 0.06 * s + rise * 0.3, -leg - bodyHeight - 0.02 * s - rise);
    }
    ctx.globalAlpha = 1;
  } else if (mood === 'working') {
    // At its laptop, hands tapping in turn, a line of text still being written.
    ctx.save();
    ctx.translate(0, 0.0125 * s * wave(0.9));
    legs(); body(); eyes('down');
    ctx.restore();
    const screenX = -0.27 * s, screenY = -leg - 0.25 * s;
    block(screenX, screenY, 0.54 * s, 0.23 * s, 0.04 * s, LAPTOP);
    ctx.globalAlpha = 0.85;
    block(screenX + 0.035 * s, screenY + 0.035 * s, 0.47 * s, 0.16 * s, 0.02 * s, SCREEN);
    ctx.globalAlpha = 0.8;
    block(screenX + 0.07 * s, screenY + 0.07 * s, 0.4 * s * Math.min(1, phase(2.6) * 1.3), 0.03 * s, 0, LAPTOP);
    ctx.globalAlpha = 1;
    block(-0.32 * s, -leg - 0.02 * s, 0.64 * s, 0.07 * s, 0.02 * s, LAPTOP);
    for (const [side, offset] of [[-1, 0], [1, 0.5]]) {
      const tap = Math.max(0, wave(0.36, offset)) * 0.07 * s;
      block(side * 0.17 * s - 0.06 * s, -leg - 0.15 * s + tap, 0.12 * s, 0.12 * s, 0.05 * s, SKIN_SHADE);
    }
  } else if (mood === 'waiting') {
    // Hops, squashed on landing, one arm waving.
    const hop = Math.abs(wave(0.76)), squash = (1 - hop) ** 3 * 0.14;
    ctx.translate(0, -hop * 0.16 * s);
    ctx.scale(1 + squash, 1 - squash);
    legs(); body([14, -128 + 16 * wave(0.38)]); eyes('wide');
  } else if (mood === 'finished') {
    // A content sway from the feet.
    ctx.translate(0, -0.03 * s * (1 + wave(0.6)));
    ctx.rotate(7 * wave(1.2) * DEG);
    legs(); body([150, -150]); eyes('happy');
  } else {
    // Slumped to one side, a drop of sweat running down now and then.
    ctx.save();
    ctx.rotate(8 * DEG);
    ctx.translate(0, 0.03 * s);
    legs(); body([12, -12]); eyes('low');
    ctx.restore();
    const p = phase(2.4);
    if (p < 0.6) {
      const r = 0.055 * s;
      ctx.globalAlpha = p < 0.1 ? p / 0.1 : 1 - Math.max(0, p - 0.45) / 0.15;
      ctx.translate(bodyWidth / 2 + 0.07 * s, -leg - bodyHeight + 0.1 * s + (p / 0.6) * 0.3 * s);
      ctx.fillStyle = SWEAT;
      ctx.beginPath();
      ctx.moveTo(0, -r * 1.8);
      ctx.quadraticCurveTo(r, -r, r, 0);
      ctx.arc(0, 0, r, 0, Math.PI);
      ctx.quadraticCurveTo(-r, -r, 0, -r * 1.8);
      ctx.fill();
    }
  }
  ctx.restore();
}

/** A companion on a canvas. The box never changes size with the mood, so what is around it stays put. */
export class Companion {
  private static all: Companion[] = [];
  private readonly ctx: CanvasRenderingContext2D;
  private size = 0;
  private mood: Mood = 'asleep';

  constructor(private readonly canvas: HTMLCanvasElement, size: number) {
    this.ctx = canvas.getContext('2d')!;
    this.resize(size);
    if (Companion.all.push(this) === 1) Companion.run();
  }

  resize(size: number) {
    if (size === this.size) return;
    const ratio = window.devicePixelRatio || 1;
    this.size = size;
    this.canvas.style.width = `${size * 1.5}px`;
    this.canvas.style.height = `${size * 1.4}px`;
    this.canvas.width = Math.round(size * 1.5 * ratio);
    this.canvas.height = Math.round(size * 1.4 * ratio);
    this.ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    this.paint(reducedMotion.matches ? STILL : performance.now() / 1000);
  }

  setMood(mood: Mood) {
    this.mood = mood;
    this.canvas.setAttribute('aria-label', MOOD_LABEL[mood]);
    if (reducedMotion.matches) this.paint(STILL);
  }

  private paint(t: number) {
    draw(this.ctx, this.mood, t, this.size, this.size * 1.5, this.size * 1.4);
  }

  /** One clock for every companion on the page. */
  private static run() {
    const frame = (now: number) => {
      if (!reducedMotion.matches) for (const companion of Companion.all) companion.paint(now / 1000);
      requestAnimationFrame(frame);
    };
    requestAnimationFrame(frame);
    reducedMotion.addEventListener('change', () => Companion.all.forEach(companion => companion.paint(STILL)));
  }
}

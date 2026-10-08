// The island: fills in and drives the markup of components/Island.astro.
import type { Band } from '../lib/demo';
import { COLOR, markSvg } from '../lib/marks';
import { Companion, moodOf } from './companion';

/** The circumference of the usage ring. */
const RING_LENGTH = 2 * Math.PI * 5.5;

/** Usage at rest, usage that deserves a look, and a limit nearly reached (LimitRing.swift). */
function usageColors(used: number) {
  if (used < 70) return { figure: '', bar: '#b4b3ae' };
  if (used < 90) return { figure: '#ecebe7', bar: '#ecebe7' };
  return { figure: 'var(--failed-text)', bar: COLOR.failed };
}

/** What the island opens on: `key` tells one content from another. */
export interface Panel {
  key: string;
  node: () => Node;
  width: number;
}

export class Island {
  readonly content: HTMLElement;
  private readonly companion: Companion;
  private readonly counters: HTMLElement;
  private readonly ring: SVGElement;
  private readonly value: SVGCircleElement;
  private readonly figure: HTMLElement;
  private shownCounters = '';
  private shownPanel: string | null = null;

  constructor(private readonly root: HTMLElement) {
    this.content = root.querySelector('.panel-content')!;
    this.counters = root.querySelector('.counters')!;
    this.ring = root.querySelector('.ring')!;
    this.value = root.querySelector('.ring .value')!;
    this.figure = root.querySelector('.pct')!;
    this.companion = new Companion(root.querySelector('canvas')!, 20);
    this.value.style.strokeDasharray = String(RING_LENGTH);
  }

  set({ counters, ring: used, mergeRequestWaits = false }: Band) {
    this.root.classList.toggle('request-waits', mergeRequestWaits);
    const mood = moodOf(counters);
    this.companion.setMood(mood);
    this.root.style.setProperty('--glow', mood === 'asleep' ? 'transparent' : COLOR[mood]);

    // A wing has room for two kinds of counter; what is merely done gives way to the others.
    const pressing = (['waiting', 'working', 'failed'] as const).filter(kind => counters[kind]);
    const shown = (['waiting', 'working', 'finished', 'failed'] as const)
      .filter(kind => counters[kind] && (kind !== 'finished' || pressing.length <= 1));
    const key = shown.map(kind => `${kind}${counters[kind]}`).join();
    if (key !== this.shownCounters) {
      this.shownCounters = key;
      this.counters.innerHTML = shown.map(kind => kind === 'waiting'
        ? `<span class="counter waiting" role="img" aria-label="${counters.waiting} waiting for you">${counters.waiting}</span>`
        : `<span class="counter ${kind}" role="img" aria-label="${counters[kind]} ${kind}">${markSvg(kind)}${counters[kind]}</span>`).join('');
    }

    // Before any figure arrives the ring is empty and dashed, with a dash for a number.
    this.ring.classList.toggle('empty', used === null);
    this.figure.textContent = used === null ? '—' : `${used}%`;
    this.figure.style.fontWeight = used !== null && used >= 90 ? '600' : '';
    if (used === null) {
      this.figure.style.color = 'var(--text3)';
    } else {
      const colors = usageColors(used);
      this.figure.style.color = colors.figure;
      this.value.style.stroke = colors.bar;
      this.value.style.strokeDashoffset = String(RING_LENGTH * (1 - used / 100));
    }
  }

  open(panel: Panel) {
    if (this.shownPanel !== panel.key) {
      this.shownPanel = panel.key;
      this.content.replaceChildren(panel.node());
      this.root.style.setProperty('--open-width', `${panel.width}px`);
    }
    this.root.classList.add('open');
  }

  /** What was shown stays in place while the island closes over it. */
  close() {
    this.root.classList.remove('open');
    this.shownPanel = null;
  }
}

/** The five states a session can be in, as the island names them. */
export type StateKind = 'waiting' | 'working' | 'finished' | 'failed' | 'unknown';

/** State colours, as in Sources/NotchApp/IslandKit.swift. */
export const COLOR: Record<StateKind, string> = {
  waiting: '#f2b441',
  working: '#c8c7c2',
  finished: '#7fb79a',
  failed: '#cf7f73',
  unknown: '#6b6a66',
};

// StateMark in IslandKit.swift: every state has a shape of its own as well as a colour.
const SHAPES: Record<StateKind, string> = {
  waiting: `<circle cx="4" cy="4" r="4" fill="${COLOR.waiting}"/>`,
  working: `<circle cx="4" cy="4" r="3.25" fill="none" stroke="${COLOR.working}" stroke-width="1.5"/>`,
  finished: `<path d="M1 4.2 3.4 6.5 8 1.5" fill="none" stroke="${COLOR.finished}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>`,
  failed: `<path d="M1.2 1.2 6.8 6.8M6.8 1.2 1.2 6.8" fill="none" stroke="${COLOR.failed}" stroke-width="1.6" stroke-linecap="round"/>`,
  unknown: `<circle cx="4" cy="4" r="3.25" fill="none" stroke="${COLOR.unknown}" stroke-width="1.5" stroke-dasharray="1.7 1.7"/>`,
};

export const markViewBox = (kind: StateKind) => (kind === 'finished' ? '0 0 9 8' : '0 0 8 8');
export const markShape = (kind: StateKind) => SHAPES[kind];

/** The mark as markup, for what the page draws after it has loaded. */
export const markSvg = (kind: StateKind) =>
  `<svg class="mark" data-mark="${kind}" viewBox="${markViewBox(kind)}" aria-hidden="true">${SHAPES[kind]}</svg>`;

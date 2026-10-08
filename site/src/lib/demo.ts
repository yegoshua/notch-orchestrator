import { COLOR, type StateKind } from './marks';

/** How many sessions are in each state; a state without sessions is left out. */
export type Counters = Partial<Record<Exclude<StateKind, 'unknown'>, number>>;

/** The line that slides out of the island by itself. */
export interface TransientLine {
  kind: StateKind;
  title: string;
  ending: string;
  project: string;
}

/** What the island shows in the band: the counters and how much of the five-hour limit is used. */
export interface Band {
  counters: Counters;
  ring: number | null;
}

/** One stop of the scene that scrolls through the island's states. */
export interface Step extends Band {
  kind: StateKind;
  label: string;
  clock: string;
  state: string;
  detail: string;
  /** The colour of the state's line; the text colour when left out. */
  color?: string;
  /** What opens below the band at this stop. */
  opens?: 'card' | TransientLine;
}

export const STEPS: Step[] = [
  {
    kind: 'unknown', label: 'Asleep', clock: '14:02', counters: {}, ring: 12, state: 'Nothing runs',
    detail: 'The companion sleeps at the left of the notch. The ring on the right is your five-hour limit.',
  },
  {
    kind: 'working', label: 'Working', clock: '14:10', counters: { working: 3 }, ring: 27, state: 'Three sessions work',
    detail: 'A count beside a mark, not a dot per session. Nothing moves except the companion at its laptop.',
  },
  {
    kind: 'waiting', label: 'Needs you', clock: '14:26', counters: { waiting: 1, working: 2 }, ring: 41,
    state: 'One needs you', color: COLOR.waiting,
    detail: 'A session wants to run a migration. The card opens under the notch: allow or deny it here.',
    opens: 'card',
  },
  {
    kind: 'failed', label: 'Failed', clock: '14:41', counters: { failed: 1, working: 2 }, ring: 58,
    state: 'One failed', color: 'var(--failed-text)',
    detail: 'A line slides out for a few seconds and goes back. Noticeable, not alarming.',
    opens: { kind: 'failed', title: 'Flaky test hunt', ending: 'failed', project: 'frontoffice' },
  },
  {
    kind: 'finished', label: 'Finished', clock: '15:20', counters: { finished: 3 }, ring: 76,
    state: 'The work is done', color: COLOR.finished,
    detail: 'Finished turns stay in the count for ten minutes unless you choose otherwise, then the island goes back to sleep.',
    opens: { kind: 'finished', title: 'Release notes', ending: 'finished', project: 'frontoffice' },
  },
];

/** The band above the scene, and below it. */
export const ABOVE_SCENE: Band = { counters: { waiting: 1, working: 2 }, ring: 41 };
export const BELOW_SCENE: Band = { counters: { working: 2, finished: 1 }, ring: 76 };
/** The band once the card of the scene has been answered. */
export const ANSWERED: Counters = { working: 3 };

/** The legend of "How to read the island": each state, and the band that shows it off. */
export const LEGEND: { kind: StateKind; name: string; means: string; counters: Counters; caption: string }[] = [
  {
    kind: 'waiting', name: 'Needs you', means: 'a permission or a question', counters: { waiting: 1, working: 2 },
    caption: 'A filled amber circle, the only state that asks something of you. The companion hops and waves.',
  },
  {
    kind: 'working', name: 'Working', means: 'the agent is running', counters: { working: 3 },
    caption: 'A hollow ring: the agent is running. The companion types.',
  },
  {
    kind: 'finished', name: 'Finished', means: 'the turn just ended', counters: { finished: 2 },
    caption: 'A green check: the turn ended a short while ago. How long it stays is yours to set.',
  },
  {
    kind: 'failed', name: 'Failed', means: 'the turn ended with an error', counters: { failed: 1, working: 2 },
    caption: 'A red cross: the turn ended with an error. The companion slumps.',
  },
  {
    kind: 'unknown', name: 'Unknown', means: 'could not be confirmed', counters: {},
    caption: 'A dashed ring: the state could not be confirmed, so the app does not guess.',
  },
];

export const RING_CHOICES: (number | null)[] = [23, 78, 96, null];

/** The sessions of the mock list, in the order the app groups them. */
export const SESSIONS: { kind: StateKind; group: string; rows: { title: string; where: string; activity: string; flag?: string; time: string }[] }[] = [
  { kind: 'waiting', group: 'Needs you', rows: [{ title: 'Migrate orders table', where: 'payments-api · CLI', activity: 'Wants to run npm run migrate', flag: 'Needs you', time: '42s' }] },
  { kind: 'failed', group: 'Failed', rows: [{ title: 'Flaky test hunt', where: 'frontoffice · CLI', activity: 'The turn ended with an error', flag: 'Failed', time: '2m ago' }] },
  {
    kind: 'working', group: 'Working', rows: [
      { title: 'Deposit widget polish', where: 'cashier-lite · Desktop', activity: 'Editing QuickDepositView.tsx · CI: test', time: '6m' },
      { title: 'Docs sweep', where: 'notch-orchestrator · VS Code', activity: 'Reading README.md · 2 subagents ▸', time: '14m' },
    ],
  },
  { kind: 'finished', group: 'Finished', rows: [{ title: 'Release notes', where: 'frontoffice · CLI', activity: 'Finished · CI passed', time: '3m ago' }] },
  { kind: 'unknown', group: 'Unknown', rows: [{ title: 'Untitled session', where: 'sandbox · CLI', activity: 'State could not be confirmed', time: '1h 00m ago' }] },
];

export const REPOSITORY = 'yegoshua/notch-orchestrator';
export const INSTALL_COMMAND = `curl -fsSL https://github.com/${REPOSITORY}/releases/latest/download/install.sh | sh`;

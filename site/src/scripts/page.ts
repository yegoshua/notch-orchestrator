// What the page does once it has loaded: the island follows the scroll, answers and opens.
import { ABOVE_SCENE, ANSWERED, BELOW_SCENE, LEGEND, MERGE_REQUESTS, REPOSITORY, STEPS, type TransientLine } from '../lib/demo';
import { COLOR, markSvg, type StateKind } from '../lib/marks';
import { Companion, MOOD_LABEL, moodOf } from './companion';
import { startDust } from './dust';
import { Island, type Panel } from './island';
import { startMotion } from './motion';
import { viewportHeight } from './viewport';

const $ = <T extends HTMLElement>(selector: string, root: ParentNode = document) => root.querySelector<T>(selector)!;
const $$ = <T extends HTMLElement>(selector: string, root: ParentNode = document) => [...root.querySelectorAll<T>(selector)];

/** How long the transient line stays out. */
const LINE_SECONDS = 4.5;
/** The companion of the scene, on a wide page and on a narrow one. */
const STAGE_SIZE = { wide: 150, narrow: 96, breakpoint: 860 };

const template = (id: string) => () => $<HTMLTemplateElement>(`#${id}`).content.cloneNode(true);
const CARD: Panel = { key: 'card', node: template('tpl-card'), width: 520 };
const LIST: Panel = { key: 'list', node: template('tpl-list'), width: 540 };

function linePanel(line: TransientLine): Panel {
  return {
    key: line.title,
    width: 405,
    node() {
      const row = $<HTMLTemplateElement>('#tpl-line').content.cloneNode(true) as DocumentFragment;
      $('.tline', row).insertAdjacentHTML('afterbegin', markSvg(line.kind));
      $('b', row).textContent = line.title;
      $('.ending', row).textContent = line.ending;
      $('.project', row).textContent = line.project;
      return row;
    },
  };
}

/** The island at the top of the page, and the scene that walks it through its states. */
function scene() {
  const island = new Island($('#island'));
  const section = $('#scene'), pin = $('#scene-pin'), stops = $$('#steps li');
  const stage = new Companion($<HTMLCanvasElement>('#scene-companion'), STAGE_SIZE.wide);
  const hotkey = $('#hotkey');

  // Where the page is: -1 above the scene, a step inside it, STEPS.length below.
  let at: number | null = null;
  let listOpen = false, lineGone = false, lineTimer = 0;
  let answer: 'allow' | 'deny' | null = null;

  function render() {
    const step = at === null ? undefined : STEPS[at];
    const band = step ?? (at !== null && at >= STEPS.length ? BELOW_SCENE : ABOVE_SCENE);
    const answered = step?.opens === 'card' ? answer : null;
    const counters = answered ? ANSWERED : band.counters;
    island.set({ counters, ring: band.ring });

    if (step) {
      const mood = moodOf(counters);
      stage.setMood(mood);
      $('#scene-mood').textContent = MOOD_LABEL[mood];
      // The state lights the scene from the notch; with nothing running the light is off.
      section.style.setProperty('--glow-color', mood === 'asleep' ? 'transparent' : COLOR[mood]);
      $('#scene-clock').textContent = step.clock;
      $('#scene-state').textContent = step.state;
      $('#scene-state').style.setProperty('--state', step.color ?? '');
      $('#scene-detail').textContent = answered === 'allow'
        ? 'Allowed. The session carries on, and you never left your editor.'
        : answered === 'deny' ? 'Denied. The agent is told, and looks for another way.' : step.detail;
    }

    hotkey.setAttribute('aria-expanded', String(listOpen));
    if (listOpen) island.open(LIST);
    else if (step?.opens === 'card' && !answered) island.open(CARD);
    else if (step?.opens && step.opens !== 'card' && !lineGone) island.open(linePanel(step.opens));
    else island.close();
  }

  function enter(next: number) {
    if (next === at) return;
    at = next;
    listOpen = false;
    answer = null;
    lineGone = false;
    clearTimeout(lineTimer);
    const opens = STEPS[at]?.opens;
    if (opens && opens !== 'card') {
      lineTimer = window.setTimeout(() => { lineGone = true; render(); }, LINE_SECONDS * 1000);
    }
    stops.forEach((stop, index) => {
      stop.classList.toggle('current', index === at);
      $('button', stop).setAttribute('aria-current', index === at ? 'step' : 'false');
    });
    render();
  }

  function onScroll() {
    // How far the pinned part has travelled through the section, in steps.
    const rect = section.getBoundingClientRect();
    const progress = -rect.top / (rect.height - pin.offsetHeight) * STEPS.length;
    stops.forEach((stop, index) => stop.style.setProperty('--p', String(Math.min(1, Math.max(0, progress - index)))));
    // The scene takes over once its pinned part has all but reached the top.
    enter(rect.top > viewportHeight() * 0.25 ? -1 : Math.min(STEPS.length, Math.max(0, Math.floor(progress))));
  }

  function layout() {
    stage.resize(innerWidth <= STAGE_SIZE.breakpoint ? STAGE_SIZE.narrow : STAGE_SIZE.wide);
    onScroll();
  }
  addEventListener('scroll', onScroll, { passive: true });
  addEventListener('resize', layout);
  layout();

  stops.forEach((stop, index) => $('button', stop).addEventListener('click', () => {
    const travel = section.offsetHeight - pin.offsetHeight;
    scrollTo({ top: section.offsetTop + travel * (index + 0.5) / STEPS.length });
  }));

  // The card answers, as it does in the app.
  function decide(act: 'allow' | 'deny') {
    if (at === null || STEPS[at]?.opens !== 'card' || answer || listOpen) return false;
    answer = act;
    render();
    return true;
  }
  island.content.addEventListener('click', event => {
    const act = (event.target as Element).closest<HTMLElement>('[data-act]')?.dataset.act;
    if (act === 'allow' || act === 'deny') decide(act);
  });

  // The hotkey that opens the list of sessions, and the two of the card.
  const keycaps = $$('kbd', hotkey);
  const toggleList = () => { listOpen = !listOpen; render(); };
  hotkey.addEventListener('click', toggleList);
  addEventListener('keydown', event => {
    keycaps.find(cap => cap.dataset.key === event.key || cap.dataset.key === event.code)?.classList.add('down');
    if (event.key === 'Escape' && listOpen) toggleList();
    if (!event.ctrlKey || !event.altKey || event.metaKey) return;
    if (event.code === 'KeyN') { event.preventDefault(); toggleList(); }
    if (event.code === 'KeyY' && decide('allow')) event.preventDefault();
    if (event.code === 'KeyX' && decide('deny')) event.preventDefault();
  });
  const release = () => keycaps.forEach(cap => cap.classList.remove('down'));
  addEventListener('keyup', release);
  addEventListener('blur', release);
}

/** "How to read the island": the open island, and the choices that change it. */
function legend() {
  const preview = new Island($('#preview'));
  let state: StateKind = 'waiting';
  let ring: number | null = 23;

  function render() {
    const entry = LEGEND.find(entry => entry.kind === state)!;
    preview.set({ counters: entry.counters, ring, mergeRequestWaits: MERGE_REQUESTS.some(request => request.waits) });
    $('#screen').style.setProperty('--glow-color', COLOR[state]);
    $('.list', preview.content).dataset.focus = state;
    $('#read-caption').textContent = entry.caption;
    for (const button of $$('#state-options button')) button.setAttribute('aria-pressed', String(button.dataset.state === state));
    for (const button of $$('#ring-options button')) button.setAttribute('aria-pressed', String(button.dataset.ring === String(ring ?? '')));
  }

  $('#state-options').addEventListener('click', event => {
    const button = (event.target as Element).closest('button');
    if (!button) return;
    state = button.dataset.state as StateKind;
    render();
  });
  $('#ring-options').addEventListener('click', event => {
    const button = (event.target as Element).closest('button');
    if (!button) return;
    ring = button.dataset.ring ? Number(button.dataset.ring) : null;
    render();
  });
  render();
}

/** The hero: the companion in the light of the notch, waving. */
function hero() {
  const size = () => (innerWidth <= STAGE_SIZE.breakpoint ? 84 : 132);
  const companion = new Companion($<HTMLCanvasElement>('#hero-companion'), size());
  addEventListener('resize', () => companion.resize(size()));
  companion.setMood('waiting');
  startDust($<HTMLCanvasElement>('#hero-dust'));
}

function install() {
  new Companion($<HTMLCanvasElement>('#install-companion'), 72).setMood('finished');
  const copy = $('#copy'), command = $('#install-command');
  copy.addEventListener('click', async () => {
    try {
      await navigator.clipboard.writeText(command.textContent ?? '');
      copy.textContent = 'Copied';
    } catch {
      getSelection()?.selectAllChildren(command);
      copy.textContent = 'Press ⌘C';
    }
    setTimeout(() => { copy.textContent = 'Copy'; }, 1800);
  });

  // The version of the latest release, when GitHub answers.
  fetch(`https://api.github.com/repos/${REPOSITORY}/releases/latest`)
    .then(response => (response.ok ? response.json() : null))
    .then(latest => {
      const version = latest?.tag_name?.replace(/^v/, '');
      if (version) $('#release').textContent = `Version ${version} · macOS 14 or later · MIT`;
    })
    .catch(() => {});
}

startMotion();
hero();
scene();
legend();
install();

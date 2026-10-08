'use strict';

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];
const reducedMotion = matchMedia('(prefers-reduced-motion: reduce)');

const COLOR = {
  waiting: '#f2b441', working: '#c8c7c2', finished: '#7fb79a', failed: '#cf7f73', unknown: '#6b6a66',
};

// ---------- State marks (StateMark in IslandKit.swift) ----------

const MARKS = {
  waiting: `<circle cx="4" cy="4" r="4" fill="${COLOR.waiting}"/>`,
  working: `<circle cx="4" cy="4" r="3.25" fill="none" stroke="${COLOR.working}" stroke-width="1.5"/>`,
  finished: `<path d="M1 4.2 3.4 6.5 8 1.5" fill="none" stroke="${COLOR.finished}" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"/>`,
  failed: `<path d="M1.2 1.2 6.8 6.8M6.8 1.2 1.2 6.8" fill="none" stroke="${COLOR.failed}" stroke-width="1.6" stroke-linecap="round"/>`,
  unknown: `<circle cx="4" cy="4" r="3.25" fill="none" stroke="${COLOR.unknown}" stroke-width="1.5" stroke-dasharray="1.7 1.7"/>`,
};

function fillMarks(root) {
  for (const svg of $$('svg.mark', root)) {
    const kind = svg.dataset.mark;
    svg.setAttribute('viewBox', kind === 'finished' ? '0 0 9 8' : '0 0 8 8');
    svg.setAttribute('aria-hidden', 'true');
    svg.innerHTML = MARKS[kind];
  }
}

// ---------- The companion (a port of Companion.swift) ----------

function moodOf(counters) {
  if (counters.waiting) return 'waiting';
  if (counters.failed) return 'failed';
  if (counters.working) return 'working';
  if (counters.finished) return 'finished';
  return 'asleep';
}

const MOOD_LABEL = {
  asleep: 'No live sessions',
  working: 'Sessions are working',
  waiting: 'A session waits for you',
  finished: 'Sessions have finished',
  failed: 'A session failed',
};

const SKIN = '#e07a52', SKIN_SHADE = '#c9643f', EYE = '#1b1410', LAPTOP = '#4a4a4a', SCREEN = '#9cc4e8', SWEAT = '#7fb3e6';
const DEG = Math.PI / 180;

/** One frame of the companion at time `t`, in a box `s` pixels tall, drawn around the canvas centre. */
function drawCompanion(ctx, mood, t, s, width, height) {
  const bodyWidth = 0.74 * s, bodyHeight = 0.56 * s, leg = 0.1 * s, corner = 0.17 * s;
  const phase = (period, offset = 0) => ((t + offset) / period) % 1;
  const wave = (period, offset = 0) => Math.sin((t / period + offset) * 2 * Math.PI);
  const block = (x, y, w, h, r, color) => {
    ctx.fillStyle = color;
    ctx.beginPath();
    ctx.roundRect(x, y, w, h, r);
    ctx.fill();
  };

  const legs = () => {
    for (const side of [-1, 1]) block(side * 0.2 * s - 0.065 * s, -leg - 0.02 * s, 0.13 * s, leg + 0.02 * s, 0.04 * s, SKIN_SHADE);
  };
  const arm = (side, degrees) => {
    ctx.save();
    ctx.translate(side * (bodyWidth / 2 - 0.02 * s), -leg - bodyHeight + 0.26 * bodyHeight);
    ctx.rotate(degrees * DEG);
    block(-0.055 * s, -0.02 * s, 0.11 * s, 0.26 * s, 0.055 * s, SKIN_SHADE);
    ctx.restore();
  };
  const body = (left, right) => {
    if (left !== undefined) { arm(-1, left); arm(1, right); }
    block(-bodyWidth / 2, -leg - bodyHeight, bodyWidth, bodyHeight, corner, SKIN);
  };
  const eyes = kind => {
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
    const breath = 1 + 0.035 * wave(2.8);
    ctx.save();
    ctx.scale(1 / Math.sqrt(breath), breath);
    legs(); body(12, -12); eyes('closed');
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
    const hop = Math.abs(wave(0.76)), squash = (1 - hop) ** 3 * 0.14;
    ctx.translate(0, -hop * 0.16 * s);
    ctx.scale(1 + squash, 1 - squash);
    legs(); body(14, -128 + 16 * wave(0.38)); eyes('wide');
  } else if (mood === 'finished') {
    ctx.translate(0, -0.03 * s * (1 + wave(0.6)));
    ctx.rotate(7 * wave(1.2) * DEG);
    legs(); body(150, -150); eyes('happy');
  } else {
    ctx.save();
    ctx.rotate(8 * DEG);
    ctx.translate(0, 0.03 * s);
    legs(); body(12, -12); eyes('low');
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

const companions = [];

function makeCompanion(canvas, size) {
  const companion = { canvas, ctx: canvas.getContext('2d'), size: 0, mood: 'asleep' };
  companion.resize = s => {
    if (s === companion.size) return;
    const ratio = window.devicePixelRatio || 1;
    companion.size = s;
    companion.width = s * 1.5;
    companion.height = s * 1.4;
    canvas.style.width = `${companion.width}px`;
    canvas.style.height = `${companion.height}px`;
    canvas.width = Math.round(companion.width * ratio);
    canvas.height = Math.round(companion.height * ratio);
    companion.ctx.setTransform(ratio, 0, 0, ratio, 0, 0);
    paint(companion, performance.now() / 1000);
  };
  companion.setMood = mood => {
    companion.mood = mood;
    if (reducedMotion.matches) paint(companion, 0.4);
  };
  companions.push(companion);
  companion.resize(size);
  return companion;
}

function paint(companion, t) {
  drawCompanion(companion.ctx, companion.mood, t, companion.size, companion.width, companion.height);
}

function tick(now) {
  if (!reducedMotion.matches) for (const companion of companions) paint(companion, now / 1000);
  requestAnimationFrame(tick);
}

// ---------- The island ----------

const RING_LENGTH = 2 * Math.PI * 5.5;

function makeIsland(root) {
  root.innerHTML = `
    <div class="island-body">
      <div class="band">
        <div class="wing wing-l"><canvas class="companion" role="img"></canvas><div class="counters"></div></div>
        <div></div>
        <div class="wing wing-r">
          <svg class="ring" viewBox="0 0 14 14" aria-hidden="true">
            <circle class="track" cx="7" cy="7" r="5.5"/>
            <circle class="value" cx="7" cy="7" r="5.5" stroke-dasharray="${RING_LENGTH}"/>
          </svg>
          <span class="pct"></span>
        </div>
      </div>
      <div class="panel"><div class="panel-clip"><div class="panel-content"></div></div></div>
    </div>`;
  const companion = makeCompanion($('canvas', root), 20);
  const counters = $('.counters', root), ring = $('.ring', root), value = $('.value', root), pct = $('.pct', root);
  const content = $('.panel-content', root);
  let shownCounters = '', shownPanel = null;

  return {
    set(counts, used) {
      const mood = moodOf(counts);
      companion.setMood(mood);
      companion.canvas.setAttribute('aria-label', MOOD_LABEL[mood]);
      root.style.setProperty('--glow', mood === 'asleep' ? 'transparent' : COLOR[mood]);

      // A wing has room for two kinds of counter; what is merely done gives way to the others.
      const kinds = ['waiting', 'working', 'failed'].filter(kind => counts[kind]);
      const shown = ['waiting', 'working', 'finished', 'failed']
        .filter(kind => counts[kind] && (kind !== 'finished' || kinds.length <= 1));
      const key = shown.map(kind => kind + counts[kind]).join();
      if (key !== shownCounters) {
        shownCounters = key;
        counters.innerHTML = shown.map(kind => kind === 'waiting'
          ? `<span class="counter waiting" role="img" aria-label="${counts.waiting} waiting for you">${counts.waiting}</span>`
          : `<span class="counter ${kind}" role="img" aria-label="${counts[kind]} ${kind}"><svg class="mark" data-mark="${kind}"></svg>${counts[kind]}</span>`).join('');
        fillMarks(counters);
      }

      const known = typeof used === 'number';
      ring.classList.toggle('empty', !known);
      pct.textContent = known ? `${used}%` : '—';
      pct.style.color = !known ? 'var(--text3)' : used < 70 ? '' : used < 90 ? '#ecebe7' : 'var(--failed-text)';
      pct.style.fontWeight = known && used >= 90 ? 600 : '';
      if (known) {
        value.style.strokeDashoffset = RING_LENGTH * (1 - used / 100);
        value.style.stroke = used < 70 ? '#b4b3ae' : used < 90 ? '#ecebe7' : COLOR.failed;
      }
    },
    /** Opens the island on `node`; `key` tells one content from another. */
    show(key, node, width) {
      if (shownPanel !== key) {
        shownPanel = key;
        content.replaceChildren(node());
        fillMarks(content);
        root.style.setProperty('--open-width', `${width}px`);
      }
      root.classList.add('open');
    },
    // What was shown stays in place while the island closes over it.
    hide() {
      root.classList.remove('open');
      shownPanel = null;
    },
    content,
  };
}

const template = id => () => $(`#${id}`).content.cloneNode(true);

function transientLine(kind, title, ending, project) {
  return () => {
    const line = document.createElement('div');
    line.className = 'tline';
    line.innerHTML = `<svg class="mark" data-mark="${kind}"></svg><b>${title}</b><span>${ending}</span><span class="project">${project}</span>`;
    return line;
  };
}

// ---------- The page ----------

const STEPS = [
  {
    clock: '14:02', counters: {}, ring: 12, state: 'Nothing runs',
    detail: 'The companion sleeps at the left of the notch. The ring on the right is your five-hour limit.',
  },
  {
    clock: '14:10', counters: { working: 3 }, ring: 27, state: 'Three sessions work',
    detail: 'A count beside a mark, not a dot per session. Nothing moves except the companion at its laptop.',
  },
  {
    clock: '14:26', counters: { waiting: 1, working: 2 }, ring: 41, state: 'One needs you', color: COLOR.waiting,
    detail: 'A session wants to run a migration. The card opens under the notch: allow or deny it here.',
    panel: { key: 'card', node: template('tpl-card'), width: 520 },
  },
  {
    clock: '14:41', counters: { failed: 1, working: 2 }, ring: 58, state: 'One failed', color: 'var(--failed-text)',
    detail: 'A line slides out for a few seconds and goes back. Noticeable, not alarming.',
    panel: { key: 'failed', node: transientLine('failed', 'Flaky test hunt', 'failed', 'frontoffice'), width: 405, brief: true },
  },
  {
    clock: '15:20', counters: { finished: 3 }, ring: 76, state: 'The work is done', color: COLOR.finished,
    detail: 'Finished turns stay in the count for ten minutes unless you choose otherwise, then the island goes back to sleep.',
    panel: { key: 'finished', node: transientLine('finished', 'Release notes', 'finished', 'frontoffice'), width: 405, brief: true },
  },
];
const HERO = { counters: { waiting: 1, working: 2 }, ring: 41 };
const AFTER = { counters: { working: 2, finished: 1 }, ring: 76 };
const LINE_SECONDS = 4.5;

const CAPTIONS = {
  waiting: { counters: { waiting: 1, working: 2 }, text: 'A filled amber circle, the only state that asks something of you. The companion hops and waves.' },
  working: { counters: { working: 3 }, text: 'A hollow ring: the agent is running. The companion types.' },
  finished: { counters: { finished: 2 }, text: 'A green check: the turn ended a short while ago. How long it stays is yours to set.' },
  failed: { counters: { failed: 1, working: 2 }, text: 'A red cross: the turn ended with an error. The companion slumps.' },
  unknown: { counters: {}, text: 'A dashed ring: the state could not be confirmed, so the app does not guess.' },
};

function start() {
  fillMarks(document);

  const island = makeIsland($('#island'));
  const scene = $('#scene'), steps = $$('#steps li');
  const sceneCompanion = makeCompanion($('#scene-companion'), 150);
  const stepColors = ['unknown', 'working', 'waiting', 'failed', 'finished'].map(kind => COLOR[kind]);
  steps.forEach((li, index) => li.style.setProperty('--c', stepColors[index]));

  // Where the page is: -1 above the scene, 0…4 inside it, 5 below.
  let step = null, listOpen = false, answered = null, lineGone = false, lineTimer = 0;

  function render() {
    const current = step < 0 ? HERO : step >= STEPS.length ? AFTER : STEPS[step];
    const isAnswered = answered && current.panel?.key === 'card';
    const counters = isAnswered ? { working: 3 } : current.counters;
    island.set(counters, current.ring);

    if (step >= 0 && step < STEPS.length) {
      sceneCompanion.setMood(moodOf(counters));
      $('#scene-clock').textContent = current.clock;
      const state = $('#scene-state');
      state.textContent = current.state;
      state.style.setProperty('--state', current.color ?? '');
      $('#scene-detail').textContent = isAnswered
        ? (answered === 'allow' ? 'Allowed. The session carries on, and you never left your editor.' : 'Denied. The agent is told, and looks for another way.')
        : current.detail;
    }

    const panel = current.panel;
    $('#hotkey').setAttribute('aria-expanded', listOpen);
    if (listOpen) island.show('list', template('tpl-list'), 540);
    else if (panel && !(panel.brief ? lineGone : answered)) island.show(panel.key, panel.node, panel.width);
    else island.hide();
  }

  function enter(next) {
    if (next === step) return;
    step = next;
    listOpen = false;
    answered = null;
    lineGone = false;
    clearTimeout(lineTimer);
    if (STEPS[step]?.panel?.brief) {
      lineTimer = setTimeout(() => { lineGone = true; render(); }, LINE_SECONDS * 1000);
    }
    steps.forEach((li, index) => {
      li.classList.toggle('current', index === step);
      $('button', li).setAttribute('aria-current', index === step ? 'step' : 'false');
    });
    render();
  }

  function onScroll() {
    const rect = scene.getBoundingClientRect(), travel = rect.height - window.innerHeight;
    const progress = -rect.top / travel * STEPS.length;
    steps.forEach((li, index) => li.style.setProperty('--p', Math.min(1, Math.max(0, progress - index))));
    // The scene takes over once its pinned part has reached the top, give or take a little.
    enter(rect.top > window.innerHeight * 0.25 ? -1 : progress >= STEPS.length ? STEPS.length : Math.max(0, Math.floor(progress)));
  }

  addEventListener('scroll', onScroll, { passive: true });

  function layout() {
    sceneCompanion.resize(innerWidth <= 860 ? 96 : 150);
    onScroll();
  }
  addEventListener('resize', layout);
  layout();

  steps.forEach((li, index) => $('button', li).addEventListener('click', () => {
    const travel = scene.offsetHeight - innerHeight;
    scrollTo({ top: scene.offsetTop + travel * (index + 0.5) / STEPS.length });
  }));

  // The card answers, as it does in the app.
  function answer(act) {
    if (STEPS[step]?.panel?.key !== 'card' || answered || listOpen) return false;
    answered = act;
    render();
    return true;
  }
  island.content.addEventListener('click', event => {
    const act = event.target.closest('[data-act]')?.dataset.act;
    if (act) answer(act);
  });

  // The hotkey that opens the list of sessions.
  const keycaps = $$('#hotkey kbd');
  const toggleList = () => { listOpen = !listOpen; render(); };
  $('#hotkey').addEventListener('click', toggleList);
  addEventListener('keydown', event => {
    keycaps.find(cap => cap.dataset.key === event.key || cap.dataset.key === event.code)?.classList.add('down');
    if (event.key === 'Escape' && listOpen) toggleList();
    if (!event.ctrlKey || !event.altKey || event.metaKey) return;
    if (event.code === 'KeyN') { event.preventDefault(); toggleList(); }
    if (event.code === 'KeyY' && answer('allow')) event.preventDefault();
    if (event.code === 'KeyX' && answer('deny')) event.preventDefault();
  });
  const release = () => keycaps.forEach(cap => cap.classList.remove('down'));
  addEventListener('keyup', release);
  addEventListener('blur', release);

  // "How to read the island".
  const preview = makeIsland($('#preview'));
  preview.show('list', template('tpl-list'), 540);
  let previewState = 'waiting', previewRing = 23;
  function renderPreview() {
    preview.set(CAPTIONS[previewState].counters, previewRing);
    $('.list', preview.content).dataset.focus = previewState;
    $('#read-caption').textContent = CAPTIONS[previewState].text;
    for (const button of $$('#state-options button')) button.setAttribute('aria-pressed', button.dataset.state === previewState);
    for (const button of $$('#ring-options button')) button.setAttribute('aria-pressed', button.dataset.ring === String(previewRing ?? ''));
  }
  $('#state-options').addEventListener('click', event => {
    const button = event.target.closest('button');
    if (!button) return;
    previewState = button.dataset.state;
    renderPreview();
  });
  $('#ring-options').addEventListener('click', event => {
    const button = event.target.closest('button');
    if (!button) return;
    previewRing = button.dataset.ring ? Number(button.dataset.ring) : null;
    renderPreview();
  });
  renderPreview();

  // The install command.
  const copy = $('#copy');
  copy.addEventListener('click', async () => {
    const command = $(`#${copy.dataset.copy}`);
    try {
      await navigator.clipboard.writeText(command.textContent);
      copy.textContent = 'Copied';
    } catch {
      getSelection().selectAllChildren(command);
      copy.textContent = 'Press ⌘C';
    }
    setTimeout(() => { copy.textContent = 'Copy'; }, 1800);
  });

  fetch('https://api.github.com/repos/yegoshua/notch-orchestrator/releases/latest')
    .then(response => response.ok ? response.json() : null)
    .then(latest => {
      const version = latest?.tag_name?.replace(/^v/, '');
      if (version) $('#release').textContent = `Version ${version} · macOS 14 or later · MIT`;
    })
    .catch(() => {});

  // Without motion each companion rests on one frame of its mood.
  reducedMotion.addEventListener('change', () => companions.forEach(companion => paint(companion, 0.4)));
  requestAnimationFrame(tick);
}

start();

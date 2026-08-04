/* main.js — the LPS(2) IDE (M14).
 *
 * Editor on the left, visualisers on the right, a splitter between them, and a
 * menu bar over the top. Everything it knows about the engine it learns from
 * /lpsapi (see api.js), which is the constraint the plan kept from the old
 * "reference client" rule: if the editor can do it, curl can do it.
 */
/*  The editor API only, not the `monaco-editor` entry point: that one pulls in
 *  every one of Monaco's ~90 bundled languages (abap, apex, bicep, …), none of
 *  which an LPS file has any use for, and it triples the build. The relative
 *  path sidesteps the package's own exports map, which does not offer this
 *  subpath. */
import * as monaco from '../node_modules/monaco-editor/esm/vs/editor/editor.api.js';
import { registerLps, LANGUAGE_ID } from './lps-language.js';
import * as api from './api.js';
import { el, empty, renderTimeline, renderChanges, renderExplanation, renderInternal } from './panes/basic.js';
import { renderAutomaton } from './panes/automaton.js';
import { renderScene2d } from './panes/scene2d.js';
import { renderScene3d } from './panes/scene3d.js';
import { mountAssistant } from './assistant.js';
import { mountLive } from './live.js';

self.MonacoEnvironment = { getWorkerUrl: () => './editor.worker.js' };

const $ = (id) => document.getElementById(id);
const store = {
  get: (k, d) => { try { return JSON.parse(localStorage.getItem('lps.' + k)) ?? d; } catch { return d; } },
  set: (k, v) => localStorage.setItem('lps.' + k, JSON.stringify(v)),
};

export const state = {
  editor: null,
  program: null,
  session: null,
  cycle: 0,
  maxCycle: 0,
  pane: store.get('pane', 'timeline'),
  fileName: 'untitled.lps',
  fileHandle: null,
  dirty: false,
  analysing: null,
};

/* ---- editor -------------------------------------------------------------- */

function makeEditor() {
  registerLps(monaco);
  const theme = store.get('theme', 'lps-dark');
  state.editor = monaco.editor.create($('editor'), {
    value: '',
    language: LANGUAGE_ID,
    theme,
    fontSize: store.get('fontSize', 13),
    minimap: { enabled: false },
    automaticLayout: true,
    scrollBeyondLastLine: false,
    renderWhitespace: 'selection',
    tabSize: 4,
  });
  document.body.dataset.theme = theme === 'lps-light' ? 'light' : 'dark';

  let timer = null;
  state.editor.onDidChangeModelContent(() => {
    state.dirty = true;
    setStatus('typing…');
    clearTimeout(timer);
    timer = setTimeout(analyseNow, 1500);       // the LE2 debounce, inherited
  });

  addEditorActions();
}

/* Diagnostics as markers, at the line and column the compiler reported
 * (§I.2.5). The failure this guards against is the reference client's: a
 * thrown analysis returns no `diagnostics` field, and treating a missing
 * field as an empty one reports "no errors" for a program that did not
 * parse — the one thing an editor must never do. api.analyse throws instead. */
async function analyseNow() {
  const model = state.editor.getModel();
  const source = model.getValue();
  if (!source.trim()) { setProblems([]); setStatus('empty'); return; }
  setStatus('analysing…');
  try {
    const diags = await api.analyse(source, syntaxOf(state.fileName));
    const markers = diags.map((d) => {
      const line = d.source?.line || 1, col = (d.source?.col || 0) + 1;
      return {
        severity: d.severity === 'error' ? monaco.MarkerSeverity.Error
          : d.severity === 'warning' ? monaco.MarkerSeverity.Warning
            : monaco.MarkerSeverity.Info,
        message: `${d.message}  [${d.code}]`,
        startLineNumber: line, startColumn: col,
        endLineNumber: line, endColumn: col + 80,
      };
    });
    monaco.editor.setModelMarkers(model, 'lps', markers);
    setProblems(diags);
    setStatus(diags.length ? `${diags.length} problem(s)` : 'no problems');
  } catch (e) {
    monaco.editor.setModelMarkers(model, 'lps', []);
    setProblems([{ severity: 'error', code: 'analysis_failed', message: e.message, source: null }]);
    setStatus('analysis failed');
  }
}

function setProblems(diags) {
  const box = $('problems');
  if (!diags.length) { box.replaceChildren(el('span', { class: 'ok', text: 'no problems' })); return; }
  box.replaceChildren(...diags.map((d) => el('div', {
    class: 'problem ' + d.severity,
    onclick: () => {
      if (!d.source) return;
      const pos = { lineNumber: d.source.line || 1, column: (d.source.col || 0) + 1 };
      state.editor.setPosition(pos);
      state.editor.revealLineInCenter(pos.lineNumber);
      state.editor.focus();
    },
  }, `${d.severity}: ${d.message}` + (d.source ? `  (line ${d.source.line})` : ''))));
}

const syntaxOf = (name) =>
  /\.(lpsw|_\.P|P)$/i.test(name) ? 'internal' : /\.le$/i.test(name) ? 'le' : 'legacy';

function addEditorActions() {
  const ed = state.editor;
  const K = monaco.KeyMod, C = monaco.KeyCode;

  ed.addAction({
    id: 'lps.run', label: 'Run', keybindings: [K.CtrlCmd | C.Enter],
    contextMenuGroupId: 'lps', contextMenuOrder: 0, run: () => runProgram(),
  });
  ed.addAction({
    id: 'lps.internal', label: 'See internal syntax',
    contextMenuGroupId: 'navigation', contextMenuOrder: 1,
    run: async () => { selectPane('internal'); await refreshPane(); },
  });
  ed.addAction({
    id: 'lps.explainThis', label: 'Explain this',
    contextMenuGroupId: 'navigation', contextMenuOrder: 2,
    run: (e) => {
      const w = termAtCursor(e);
      if (!w) return;
      selectPane('explain');
      $('ask').value = `why(happened(${w}), ${state.cycle || 1})`;
      askExplain();
    },
  });
  ed.addAction({
    id: 'lps.observeThis', label: 'Observe this (live session)',
    contextMenuGroupId: 'navigation', contextMenuOrder: 3,
    run: (e) => {
      const w = termAtCursor(e);
      if (w) window.dispatchEvent(new CustomEvent('lps-observe', { detail: w }));
    },
  });
  ed.addAction({
    id: 'lps.showDefinition', label: 'Show definition',
    contextMenuGroupId: 'navigation', contextMenuOrder: 4,
    keybindings: [K.CtrlCmd | C.F12],
    run: (e) => jumpToDefinition(e),
  });
  ed.addAction({
    id: 'lps.showOccurrences', label: 'Show occurrences',
    contextMenuGroupId: 'navigation', contextMenuOrder: 5,
    run: (e) => showOccurrences(e),
  });
  ed.addAction({
    id: 'lps.copyUrl', label: 'Copy URL', contextMenuGroupId: 'navigation', contextMenuOrder: 9,
    run: () => copyShareLink(),
  });
}

function termAtCursor(ed) {
  const model = ed.getModel(), pos = ed.getPosition();
  const line = model.getLineContent(pos.lineNumber);
  //  A term is a name plus a balanced argument list; scan out from the word.
  const w = model.getWordAtPosition(pos);
  if (!w) return null;
  let i = w.endColumn - 1;
  if (line[i] !== '(') return w.word;
  let depth = 0;
  for (; i < line.length; i++) {
    if (line[i] === '(') depth++;
    else if (line[i] === ')') { depth--; if (!depth) return line.slice(w.startColumn - 1, i + 1); }
  }
  return w.word;
}

/* Definitions and occurrences are a text search over the buffer, deliberately.
 * The alternative is asking the server for the clause index, which would be a
 * better answer and a worse trade: it would stop working the moment the buffer
 * does not compile, which is exactly when you are looking for a definition. */
function clauseHeads(model, name) {
  const out = [];
  const lines = model.getLinesContent();
  const head = new RegExp(`^\\s*(${name})\\s*(\\(|\\s+(if|initiates|terminates|updates|at|from)\\b|\\.)`);
  lines.forEach((l, i) => { if (head.test(l)) out.push(i + 1); });
  return out;
}

function jumpToDefinition(ed) {
  const w = ed.getModel().getWordAtPosition(ed.getPosition());
  if (!w) return;
  const hits = clauseHeads(ed.getModel(), w.word);
  if (!hits.length) { setStatus(`no definition of ${w.word} in this file`); return; }
  state.jumpBack = ed.getPosition();
  ed.setPosition({ lineNumber: hits[0], column: 1 });
  ed.revealLineInCenter(hits[0]);
}

function showOccurrences(ed) {
  const w = ed.getModel().getWordAtPosition(ed.getPosition());
  if (!w) return;
  const matches = ed.getModel().findMatches(w.word, true, false, true, null, false);
  openDialog(`Occurrences of ${w.word} (${matches.length})`,
    el('div', { class: 'list' }, ...matches.map((m) => el('div', {
      class: 'row', onclick: () => {
        ed.setPosition({ lineNumber: m.range.startLineNumber, column: m.range.startColumn });
        ed.revealLineInCenter(m.range.startLineNumber);
        closeDialog();
      },
    }, `${m.range.startLineNumber}: ${ed.getModel().getLineContent(m.range.startLineNumber).trim()}`))));
}

/* ---- running ------------------------------------------------------------- */

async function runProgram(cycles) {
  const source = state.editor.getValue();
  setStatus('compiling…');
  try {
    const c = await api.compile(source, syntaxOf(state.fileName));
    state.program = c.program;
    const s = await api.sessionNew(c.program);
    state.session = s.session;
    setStatus('running…');
    const r = await api.run(state.session, cycles);
    state.maxCycle = r.cycle;
    state.cycle = Math.min(state.cycle || 0, state.maxCycle);
    setStatus(`${r.status} after ${r.cycle} cycles`);
    //  Land on cycle 1 rather than 0: cycle 0 is the initial state and has no
    //  changes to show, so every pane would open empty on a program that ran.
    if (!state.cycle) state.cycle = Math.min(1, state.maxCycle);
    $('cycle-slider').max = String(state.maxCycle);
    $('cycle-slider').value = String(state.cycle);
    $('cycle-label').textContent = `cycle ${state.cycle}`;
    await refreshPane();
    window.dispatchEvent(new CustomEvent('lps-ran', { detail: state }));
  } catch (e) {
    setStatus('error: ' + e.message);
    await analyseNow();
  }
}

/* ---- panes --------------------------------------------------------------- */

const PANES = [
  ['timeline', 'timeline'],
  ['changes', 'state changes'],
  ['automaton', 'state transitions'],
  ['scene', '2D'],
  ['scene3d', '3D'],
  ['explain', 'explain'],
  ['internal', 'internal syntax'],
];

function selectPane(id) {
  state.pane = id; store.set('pane', id);
  for (const b of document.querySelectorAll('#tabs button')) b.classList.toggle('on', b.dataset.pane === id);
  for (const p of document.querySelectorAll('.pane')) p.classList.toggle('on', p.id === 'pane-' + id);
}

async function refreshPane() {
  const pane = $('pane-' + state.pane);
  if (!pane) return;
  if (state.pane === 'internal') {
    if (!state.program) return empty(pane, 'Run a program first.');
    const d = await api.dump(state.program);
    return renderInternal(pane, d.dump);
  }
  if (!state.session) return empty(pane, 'Run a program first (Ctrl/Cmd + Enter).');
  try {
    switch (state.pane) {
      case 'timeline': {
        const t = await api.timeline(state.session);
        return renderTimeline(pane, t, state.cycle, (c) => setCycle(c));
      }
      case 'changes': {
        const c = await api.changes(state.session, Math.max(1, state.cycle));
        return renderChanges(pane, c);
      }
      case 'automaton': {
        const a = await api.automaton(state.session, {
          abstract_numbers: $('dfa-abstract')?.checked || false,
          non_reflexive: $('dfa-nonreflexive')?.checked || false,
        });
        return renderAutomaton(pane, a);
      }
      case 'scene': {
        const s = await api.scene(state.session, state.cycle);
        return renderScene2d(pane, s, state.cycle);
      }
      case 'scene3d': {
        const s = await api.scene3d(state.session, state.cycle);
        return renderScene3d(pane, s, state.cycle);
      }
      case 'explain':
        return;                                  // driven by the ask box
    }
  } catch (e) {
    empty(pane, e.message);
  }
}

function setCycle(c) {
  state.cycle = c;
  $('cycle-slider').value = String(c);
  $('cycle-label').textContent = `cycle ${c}`;
  refreshPane();
}

async function askExplain() {
  const q = $('ask').value.trim();
  if (!q || !state.session) return;
  const pane = $('pane-explain');
  try {
    const e = await api.explain(state.session, q);
    renderExplanation(pane, e);
  } catch (err) { empty(pane, err.message); }
}

/* ---- menus, files, dialogs ------------------------------------------------ */

function openDialog(title, body, actions) {
  $('dialog-title').textContent = title;
  $('dialog-body').replaceChildren(body);
  $('dialog-actions').replaceChildren(...(actions || [el('button', { text: 'Close', onclick: closeDialog })]));
  $('dialog').classList.add('on');
}
export function closeDialog() { $('dialog').classList.remove('on'); }

async function openExamples() {
  const body = el('div', { class: 'examples' }, el('p', { class: 'empty', text: 'loading…' }));
  openDialog('Open example from server', body);
  const r = await api.listExamples();
  const filter = el('input', { class: 'filter', placeholder: 'filter…' });
  const list = el('div', { class: 'list' });
  const draw = () => {
    const f = filter.value.toLowerCase();
    list.replaceChildren(...r.examples
      .filter((x) => !f || x.name.toLowerCase().includes(f) || (x.title || '').toLowerCase().includes(f))
      .map((x) => el('div', {
        class: 'row', onclick: async () => {
          const e = await api.example(x.name);
          loadSource(e.source, x.name.split('/').pop() + (x.name.endsWith('.lps') ? '' : ''));
          closeDialog();
        },
      },
      el('span', { class: 'ex-name', text: x.name }),
      el('span', { class: 'ex-title', text: x.title || '' }))));
  };
  filter.addEventListener('input', draw);
  body.replaceChildren(filter, list);
  draw();
  filter.focus();
}

function loadSource(text, name) {
  state.editor.setValue(text);
  state.fileName = name || 'untitled.lps';
  state.fileHandle = null;
  state.session = null; state.program = null; state.cycle = 0; state.maxCycle = 0;
  $('filename').textContent = state.fileName;
  analyseNow();
}

async function fileOpen() {
  if (window.showOpenFilePicker) {
    try {
      const [h] = await window.showOpenFilePicker({
        types: [{ description: 'LPS', accept: { 'text/plain': ['.lps', '.pl', '.lpsw', '.le', '.P'] } }],
      });
      const f = await h.getFile();
      loadSource(await f.text(), f.name);
      state.fileHandle = h;
      return;
    } catch { return; }
  }
  $('file-input').click();
}

async function fileSave(saveAs) {
  const text = state.editor.getValue();
  if (!saveAs && state.fileHandle) {
    const w = await state.fileHandle.createWritable();
    await w.write(text); await w.close();
    state.dirty = false; setStatus('saved');
    return;
  }
  if (window.showSaveFilePicker) {
    try {
      const h = await window.showSaveFilePicker({ suggestedName: state.fileName });
      const w = await h.createWritable();
      await w.write(text); await w.close();
      state.fileHandle = h; state.fileName = h.name;
      $('filename').textContent = state.fileName;
      state.dirty = false; setStatus('saved');
      return;
    } catch { return; }
  }
  const a = document.createElement('a');
  a.href = URL.createObjectURL(new Blob([text], { type: 'text/plain' }));
  a.download = state.fileName;
  a.click();
}

function copyShareLink() {
  const u = new URL(location.href);
  u.hash = '#p=' + encodeURIComponent(btoa(unescape(encodeURIComponent(state.editor.getValue()))));
  navigator.clipboard?.writeText(u.toString());
  setStatus('link copied');
}

function loadFromHash() {
  const m = /#p=([^&]+)/.exec(location.hash);
  if (!m) return false;
  try {
    loadSource(decodeURIComponent(escape(atob(decodeURIComponent(m[1])))), 'shared.lps');
    return true;
  } catch { return false; }
}

function setTheme(t) {
  monaco.editor.setTheme(t);
  store.set('theme', t);
  document.body.dataset.theme = t === 'lps-light' ? 'light' : 'dark';
}

function setFontSize(n) {
  state.editor.updateOptions({ fontSize: n });
  store.set('fontSize', n);
}

function buildMenus() {
  const menu = (name, items) => {
    const d = el('div', { class: 'menu' }, el('span', { class: 'menu-title', text: name }));
    const drop = el('div', { class: 'dropdown' });
    for (const it of items) {
      if (it === '-') { drop.appendChild(el('div', { class: 'sep' })); continue; }
      if (it.href) {
        drop.appendChild(el('a', { class: 'item', href: it.href, target: '_blank', rel: 'noopener', text: it.label }));
      } else {
        drop.appendChild(el('div', { class: 'item', text: it.label, onclick: () => { it.run(); d.classList.remove('open'); } }));
      }
    }
    d.appendChild(drop);
    d.addEventListener('click', (e) => {
      if (e.target.closest('.dropdown')) return;
      const open = d.classList.contains('open');
      for (const o of document.querySelectorAll('.menu.open')) o.classList.remove('open');
      d.classList.toggle('open', !open);
    });
    return d;
  };
  document.addEventListener('click', (e) => {
    if (!e.target.closest('.menu')) for (const o of document.querySelectorAll('.menu.open')) o.classList.remove('open');
  });

  const ed = () => state.editor;
  $('menubar').replaceChildren(
    menu('File', [
      { label: 'New', run: () => loadSource('maxTime(10).\n\n', 'untitled.lps') },
      { label: 'Open…', run: fileOpen },
      { label: 'Open example from server…', run: openExamples },
      '-',
      { label: 'Save', run: () => fileSave(false) },
      { label: 'Save As…', run: () => fileSave(true) },
      '-',
      { label: 'Copy share link', run: copyShareLink },
    ]),
    menu('Edit', [
      { label: 'Undo', run: () => ed().trigger('menu', 'undo') },
      { label: 'Redo', run: () => ed().trigger('menu', 'redo') },
      '-',
      { label: 'Find', run: () => ed().trigger('menu', 'actions.find') },
      { label: 'Replace', run: () => ed().trigger('menu', 'editor.action.startFindReplaceAction') },
      '-',
      { label: 'Toggle line comment', run: () => ed().trigger('menu', 'editor.action.commentLine') },
      { label: 'Toggle block comment', run: () => ed().trigger('menu', 'editor.action.blockComment') },
      '-',
      { label: 'Collapse all', run: () => ed().trigger('menu', 'editor.foldAll') },
      { label: 'Expand all', run: () => ed().trigger('menu', 'editor.unfoldAll') },
      '-',
      { label: 'Observations…', run: openObservations },
    ]),
    menu('Misc', [
      { label: 'Theme: dark', run: () => setTheme('lps-dark') },
      { label: 'Theme: light', run: () => setTheme('lps-light') },
      { label: 'Theme: high contrast', run: () => setTheme('lps-hc') },
      '-',
      { label: 'Font: small', run: () => setFontSize(11) },
      { label: 'Font: medium', run: () => setFontSize(13) },
      { label: 'Font: large', run: () => setFontSize(16) },
      '-',
      { label: 'API keys & Assistant settings…', run: () => window.dispatchEvent(new Event('lps-open-settings')) },
      { label: 'Server token…', run: openTokenDialog },
      '-',
      { label: 'Deploy as WASM…', run: () => window.dispatchEvent(new Event('lps-deploy-wasm')) },
    ]),
    menu('Help', [
      { label: 'Language reference', href: '/docs/lps_summary' },
      { label: 'Tutorial', href: '/docs/lps_tutorial' },
      { label: 'The IDE', href: '/docs/ide' },
      { label: 'The plan', href: '/docs/LPSplusLLM' },
      '-',
      { label: 'About', run: showAbout },
    ]),
  );
}

function openObservations() {
  const ta = el('textarea', { class: 'obs', rows: '8' });
  ta.value = state.editor.getValue().split('\n').filter((l) => /^\s*observe\b/.test(l)).join('\n');
  openDialog('Observations — timed events this program receives', ta, [
    el('button', { text: 'Cancel', onclick: closeDialog }),
    el('button', {
      class: 'primary', text: 'Replace in program', onclick: () => {
        const kept = state.editor.getValue().split('\n').filter((l) => !/^\s*observe\b/.test(l));
        state.editor.setValue(kept.join('\n').replace(/\n+$/, '\n') + '\n' + ta.value + '\n');
        closeDialog();
      },
    }),
  ]);
}

function openTokenDialog() {
  const inp = el('input', { type: 'password', value: api.getToken(), placeholder: 'LPS_TOKEN' });
  openDialog('Server token', el('div', {}, el('p', { text: 'Required when the server was started with LPS_TOKEN set.' }), inp), [
    el('button', { text: 'Cancel', onclick: closeDialog }),
    el('button', { class: 'primary', text: 'Save', onclick: () => { api.setToken(inp.value); closeDialog(); } }),
  ]);
}

function showAbout() {
  openDialog('LPS(2)', el('div', { class: 'about' },
    el('p', { text: 'A reimplementation of the LPS engine in SWI-Prolog, held to the old engine’s own corpus trace-for-trace.' }),
    el('p', { text: 'Icons: OpenMoji (CC BY-SA 4.0) and game-icons.net (CC BY 3.0). Monaco, Konva, three.js and dagre are MIT.' }),
    el('p', { class: 'muted', text: 'Build ' + (window.LPS_BUILD || 'dev') })));
}

/* ---- splitter ------------------------------------------------------------ */

function makeSplitter() {
  const sp = $('splitter'), left = $('left'), root = $('workbench');
  let drag = null;
  const setPct = (pct) => {
    const p = Math.max(15, Math.min(85, pct));
    root.style.gridTemplateColumns = `${p}% 6px 1fr`;
    store.set('split', p);
  };
  setPct(store.get('split', 50));
  sp.addEventListener('pointerdown', (e) => {
    drag = true; sp.setPointerCapture(e.pointerId); document.body.classList.add('dragging');
  });
  sp.addEventListener('pointermove', (e) => {
    if (!drag) return;
    const r = root.getBoundingClientRect();
    setPct(((e.clientX - r.left) / r.width) * 100);
  });
  const stop = (e) => {
    if (!drag) return;
    drag = false; document.body.classList.remove('dragging');
    try { sp.releasePointerCapture(e.pointerId); } catch { /* gone */ }
  };
  sp.addEventListener('pointerup', stop);
  sp.addEventListener('pointercancel', stop);
  sp.addEventListener('dblclick', () => setPct(50));
}

/* ---- status -------------------------------------------------------------- */

export function setStatus(msg) { $('status').textContent = msg; }

/* ---- boot ---------------------------------------------------------------- */

async function boot() {
  makeEditor();
  buildMenus();
  makeSplitter();

  $('tabs').replaceChildren(...PANES.map(([id, label]) => el('button', {
    'data-pane': id, text: label, onclick: () => { selectPane(id); refreshPane(); },
  })));
  selectPane(state.pane);

  $('run').addEventListener('click', () => runProgram());
  $('cycle-slider').addEventListener('input', (e) => setCycle(Number(e.target.value)));
  $('ask-go').addEventListener('click', askExplain);
  $('ask').addEventListener('keydown', (e) => { if (e.key === 'Enter') askExplain(); });
  $('file-input').addEventListener('change', async (e) => {
    const f = e.target.files[0];
    if (f) loadSource(await f.text(), f.name);
  });
  for (const id of ['dfa-abstract', 'dfa-nonreflexive']) {
    $(id)?.addEventListener('change', () => refreshPane());
  }
  $('dialog-close').addEventListener('click', closeDialog);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeDialog(); });

  mountAssistant({ state, api, setStatus, openDialog, closeDialog, el });
  mountLive({ state, api, setStatus, el, refreshPane, setCycle });

  /* A handle for the browser tests and the tutorial's screenshot script.
   * Monaco is bundled, so `window.monaco` does not exist; without this a test
   * cannot put a program in the editor. */
  window.LPS = { state, api, monaco, load: loadSource, run: runProgram, pane: selectPane, refresh: refreshPane, setCycle };

  if (!loadFromHash()) {
    try {
      const e = await api.example('goat_declarative');
      loadSource(e.source, 'goat_declarative.pl');
    } catch {
      loadSource('maxTime(10).\n\n', 'untitled.lps');
    }
  }
}

boot();

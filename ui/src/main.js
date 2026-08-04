/* main.js — the LPS2 IDE (M14).
 *
 * Editor on the left, visualisers on the right, a splitter between them, and a
 * menu bar over the top. Everything it knows about the engine it learns from
 * /lpsapi (see api.js), which is the constraint the plan kept from the old
 * "reference client" rule: if the editor can do it, curl can do it.
 *
 * Three things are worth knowing before reading further:
 *
 *   * **Several files are open at once** (tabs.js). Everything to the right of
 *     the splitter is about the file whose tab is lit, including its run.
 *   * **Monaco's own features are opt-in** (monaco-contrib.js). The API entry
 *     point ships no context menu, no find widget and no folding.
 *   * **There is no explain pane.** "Why did that happen?" is asked by
 *     right-clicking the thing, in whichever visualiser drew it (why.js).
 */
/*  The editor API only, not the `monaco-editor` entry point: that one pulls in
 *  every one of Monaco's ~90 bundled languages (abap, apex, bicep, …), none of
 *  which an LPS file has any use for, and it triples the build. The relative
 *  path sidesteps the package's own exports map, which does not offer this
 *  subpath. */
import * as monaco from '../node_modules/monaco-editor/esm/vs/editor/editor.api.js';
import './monaco-contrib.js';
import { registerLps, LANGUAGE_ID, setVocabulary } from './lps-language.js';
import * as api from './api.js';
import { el, empty, renderTimeline, renderChanges, renderExplanation, renderInternal } from './panes/basic.js';
import { renderAutomaton } from './panes/automaton.js';
import { renderScene2d } from './panes/scene2d.js';
import { renderScene3d } from './panes/scene3d.js';
import { mountAssistant } from './assistant.js';
import { mountLive } from './live.js';
import * as tabs from './tabs.js';
import { initWhy, wireWhy, openWhy } from './why.js';

self.MonacoEnvironment = { getWorkerUrl: () => './editor.worker.js' };

const $ = (id) => document.getElementById(id);
const store = {
  get: (k, d) => { try { return JSON.parse(localStorage.getItem('lps.' + k)) ?? d; } catch { return d; } },
  set: (k, v) => localStorage.setItem('lps.' + k, JSON.stringify(v)),
};

/*  `state` mirrors the active tab. The assistant, the live panel and the panes
 *  all read it, and mirroring is cheaper than teaching each of them about
 *  tabs — the one rule is that anything written here on behalf of a file must
 *  also be written back to its tab (see syncToTab). */
export const state = {
  editor: null,
  program: null,
  session: null,
  cycle: 0,
  maxCycle: 0,
  profile: null,
  pane: store.get('pane', 'timeline'),
  fileName: 'untitled.lps',
  fileHandle: null,
  dirty: false,
  live: null,
};

function syncFromTab(t) {
  state.program = t.program; state.session = t.session;
  state.cycle = t.cycle; state.maxCycle = t.maxCycle;
  state.profile = t.profile; state.fileName = t.name;
  state.fileHandle = t.handle; state.dirty = t.dirty;
  $('cycle-slider').max = String(t.maxCycle);
  $('cycle-slider').value = String(t.cycle);
  $('cycle-label').textContent = `cycle ${t.cycle}`;
  window.dispatchEvent(new CustomEvent('lps-profile', { detail: t.profile }));
  setStatus(t.lastRun || 'ready');
  refreshPane();
  analyseNow();
}

function syncToTab() {
  const t = tabs.activeTab();
  if (!t) return;
  t.program = state.program; t.session = state.session;
  t.cycle = state.cycle; t.maxCycle = state.maxCycle;
  t.profile = state.profile; t.handle = state.fileHandle;
  t.dirty = state.dirty;
}

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
    contextmenu: true,
    //  Both halves of what VS Code does with a selection: light up the other
    //  occurrences of the selected text, and of the word under the cursor.
    selectionHighlight: true,
    occurrencesHighlight: 'singleFile',
    folding: true,
    foldingStrategy: 'auto',
    showFoldingControls: 'always',
    //  Diagnostics live in the editor now, so the ruler and the overview need
    //  to carry them.
    renderValidationDecorations: 'on',
    quickSuggestions: { other: true, comments: false, strings: false },
  });
  document.body.dataset.theme = theme === 'lps-light' ? 'light' : 'dark';

  tabs.initTabs(monaco, state.editor, (t) => { syncFromTab(t); });
  tabs.mountTabs($('filetabs'));

  let timer = null;
  state.editor.onDidChangeModelContent(() => {
    //  Loading a file is not editing it. Without this guard every freshly
    //  opened tab is born with an unsaved-changes dot.
    if (!tabs.isLoading()) {
      state.dirty = true;
      const t = tabs.activeTab();
      if (t && !t.dirty) { t.dirty = true; tabs.renderTabs(); }
    }
    clearTimeout(timer);
    timer = setTimeout(analyseNow, 1200);       // the LE2 debounce, inherited
  });

  addEditorActions();
}

/* Diagnostics as markers, at the line and column the compiler reported
 * (§I.2.5) — and *only* as markers. There used to be a strip under the editor
 * repeating them; it took vertical space to say "no problems" 95% of the time,
 * and it put the message a long way from the line it was about. Monaco already
 * has three places for this: the squiggle, the hover, and the overview ruler.
 * What was missing was the contributions that make those work, which is what
 * monaco-contrib.js imports. The count in the top bar is the last piece: click
 * it to jump to the first, F8 to walk them.
 *
 * The failure this guards against is the reference client's: a thrown analysis
 * returns no `diagnostics` field, and treating a missing field as an empty one
 * reports "no errors" for a program that did not parse — the one thing an
 * editor must never do. api.analyse throws instead. */
async function analyseNow() {
  const model = state.editor.getModel();
  if (!model) return;
  const source = model.getValue();
  if (!source.trim()) { setProblemCount([]); return; }
  try {
    const r = await api.analyseFull(source, tabs.syntaxOf(state.fileName));
    if (state.editor.getModel() !== model) return;      // the user switched tabs
    const diags = r.diagnostics || [];
    monaco.editor.setModelMarkers(model, 'lps', diags.map((d) => {
      const line = d.source?.line || 1, col = (d.source?.col || 0) + 1;
      return {
        severity: d.severity === 'error' ? monaco.MarkerSeverity.Error
          : d.severity === 'warning' ? monaco.MarkerSeverity.Warning
            : monaco.MarkerSeverity.Info,
        message: `${d.message}  [${d.code}]`,
        startLineNumber: line, startColumn: col,
        endLineNumber: line, endColumn: Math.max(col + 1, model.getLineMaxColumn(Math.min(line, model.getLineCount()))),
      };
    }));
    setProblemCount(diags);
    state.profile = r.profile || null;
    syncToTab();
    setVocabulary(state.profile);
    window.dispatchEvent(new CustomEvent('lps-profile', { detail: state.profile }));
  } catch (e) {
    monaco.editor.setModelMarkers(model, 'lps', [{
      severity: monaco.MarkerSeverity.Error, message: e.message,
      startLineNumber: 1, startColumn: 1, endLineNumber: 1, endColumn: 2,
    }]);
    setProblemCount([{ severity: 'error' }]);
  }
}

function setProblemCount(diags) {
  const errs = diags.filter((d) => d.severity === 'error').length;
  const warns = diags.length - errs;
  const s = $('status');
  s.classList.toggle('has-errors', errs > 0);
  s.classList.toggle('has-warnings', !errs && warns > 0);
  if (!diags.length) { s.textContent = state.session ? s.textContent : 'no problems'; return; }
  s.textContent = [errs && `${errs} error${errs > 1 ? 's' : ''}`,
    warns && `${warns} warning${warns > 1 ? 's' : ''}`].filter(Boolean).join(', ');
}

function addEditorActions() {
  const ed = state.editor;
  const K = monaco.KeyMod, C = monaco.KeyCode;

  ed.addAction({
    id: 'lps.run', label: 'Run', keybindings: [K.CtrlCmd | C.Enter],
    contextMenuGroupId: 'lps', contextMenuOrder: 0, run: () => runProgram(),
  });
  ed.addAction({
    id: 'lps.internal', label: 'See internal syntax',
    contextMenuGroupId: 'lps', contextMenuOrder: 1,
    run: async () => { selectPane('internal'); await refreshPane(); },
  });
  ed.addAction({
    id: 'lps.explainThis', label: 'Why did this happen?',
    contextMenuGroupId: 'lps', contextMenuOrder: 2,
    run: (e) => {
      const w = termAtCursor(e);
      if (w) openWhy({ term: w, kind: 'event', cycle: state.cycle || 1 });
    },
  });
  ed.addAction({
    id: 'lps.observeThis', label: 'Observe this (live session)',
    contextMenuGroupId: 'lps', contextMenuOrder: 3,
    run: (e) => {
      const w = termAtCursor(e);
      if (w) window.dispatchEvent(new CustomEvent('lps-observe', { detail: w }));
    },
  });

  ed.addAction({
    id: 'lps.showDefinition', label: 'Show definition',
    contextMenuGroupId: 'navigation', contextMenuOrder: 1,
    keybindings: [K.CtrlCmd | C.F12],
    run: (e) => jumpToDefinition(e),
  });
  ed.addAction({
    id: 'lps.goBack', label: 'Go back (to where you jumped from)',
    contextMenuGroupId: 'navigation', contextMenuOrder: 2,
    run: () => {
      if (!state.jumpBack) return;
      ed.setPosition(state.jumpBack);
      ed.revealLineInCenter(state.jumpBack.lineNumber);
      state.jumpBack = null;
    },
  });
  ed.addAction({
    id: 'lps.showOccurrences', label: 'Show occurrences',
    contextMenuGroupId: 'navigation', contextMenuOrder: 3,
    run: (e) => showOccurrences(e),
  });
  ed.addAction({
    id: 'lps.foldPredicate', label: 'Fold all clauses for this predicate',
    contextMenuGroupId: 'navigation', contextMenuOrder: 4,
    run: (e) => foldPredicate(e, true),
  });
  ed.addAction({
    id: 'lps.unfoldPredicate', label: 'Unfold all clauses for this predicate',
    contextMenuGroupId: 'navigation', contextMenuOrder: 5,
    run: (e) => foldPredicate(e, false),
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

/*  Folding by predicate, LE2's idea. Monaco's folding ranges are indentation
 *  based and a Prolog clause is not indented, so ask for the ranges that start
 *  on this predicate's clause heads. */
function foldPredicate(ed, fold) {
  const w = ed.getModel().getWordAtPosition(ed.getPosition());
  if (!w) return;
  const lines = clauseHeads(ed.getModel(), w.word);
  if (!lines.length) { setStatus(`no clauses for ${w.word}`); return; }
  ed.trigger('lps', fold ? 'editor.fold' : 'editor.unfold', { selectionLines: lines });
  setStatus(`${fold ? 'folded' : 'unfolded'} ${lines.length} clause(s) of ${w.word}`);
}

/* ---- running ------------------------------------------------------------- */

async function runProgram(cycles) {
  const source = state.editor.getValue();
  setStatus('compiling…');
  try {
    const c = await api.compile(source, tabs.syntaxOf(state.fileName));
    state.program = c.program;
    const s = await api.sessionNew(c.program);
    state.session = s.session;
    setStatus('running…');
    const r = await api.run(state.session, cycles);
    state.maxCycle = r.cycle;
    state.cycle = Math.min(state.cycle || 0, state.maxCycle);
    setStatus(`${r.status} after ${r.cycle} cycles`);
    { const t0 = tabs.activeTab(); if (t0) t0.lastRun = `${r.status} after ${r.cycle} cycles`; }
    //  Land on cycle 1 rather than 0: cycle 0 is the initial state and has no
    //  changes to show, so every pane would open empty on a program that ran.
    if (!state.cycle) state.cycle = Math.min(1, state.maxCycle);
    $('cycle-slider').max = String(state.maxCycle);
    $('cycle-slider').value = String(state.cycle);
    $('cycle-label').textContent = `cycle ${state.cycle}`;
    syncToTab();
    tabs.renderTabs();
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
  wireWhy(pane);
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
        return renderChanges(pane, c, state.cycle);
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
    }
  } catch (e) {
    empty(pane, e.message);
  }
}

function setCycle(c) {
  state.cycle = c;
  $('cycle-slider').value = String(c);
  $('cycle-label').textContent = `cycle ${c}`;
  syncToTab();
  refreshPane();
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
  const list = el('div', { class: 'list cols' });
  const draw = () => {
    const f = filter.value.toLowerCase();
    list.replaceChildren(...r.examples
      .filter((x) => !f || x.name.toLowerCase().includes(f) || (x.title || '').toLowerCase().includes(f))
      .map((x) => el('div', {
        class: 'row', onclick: async () => {
          const e = await api.example(x.name);
          loadSource(e.source, x.name.split('/').pop());
          closeDialog();
        },
      },
      el('span', { class: 'ex-name', text: x.name }),
      el('span', { class: 'ex-title', text: x.title || '' }))));
  };
  filter.addEventListener('input', draw);
  //  A draggable divider between the two columns: names are long in one corpus
  //  directory and short in another, and no fixed width suits both.
  const grip = el('div', { class: 'colgrip', title: 'Drag to resize the name column' });
  const setCol = (px) => {
    const w = Math.max(120, Math.min(700, px));
    list.style.setProperty('--ex-name-w', w + 'px');
    store.set('exNameW', w);
  };
  setCol(store.get('exNameW', 300));
  grip.addEventListener('pointerdown', (e) => {
    grip.setPointerCapture(e.pointerId);
    const move = (ev) => setCol(ev.clientX - list.getBoundingClientRect().left);
    const up = () => { grip.removeEventListener('pointermove', move); grip.removeEventListener('pointerup', up); };
    grip.addEventListener('pointermove', move);
    grip.addEventListener('pointerup', up);
  });
  body.replaceChildren(filter, el('div', { class: 'exwrap' }, list, grip));
  draw();
  filter.focus();
}

function loadSource(text, name, opts) {
  const t = tabs.openOrReuse(text, name || 'untitled.lps', opts);
  syncFromTab(t);
  return t;
}

/*  PDDL and Drools are opened like any other file: the server converts them and
 *  hands back LPS with a header saying where it came from. §IV.4's point is
 *  that a front end is a *door*, not a fork, and the door should be the one
 *  everything else uses. */
async function loadPossiblyForeign(text, name) {
  if (!/\.(pddl|drl)$/i.test(name)) return loadSource(text, name);
  setStatus(`converting ${name}…`);
  try {
    const r = await api.api({ operation: 'convert', source: text, name });
    if (r.diagnostics?.length) {
      setStatus(`${name}: ${r.diagnostics.length} conversion note(s) — see the comments`);
    } else setStatus(`converted ${name}`);
    return loadSource(r.source, r.name, { origin: name });
  } catch (e) {
    setStatus(`could not convert ${name}: ${e.message}`);
    return loadSource(text, name);
  }
}

async function fileOpen() {
  if (window.showOpenFilePicker) {
    try {
      const hs = await window.showOpenFilePicker({
        multiple: true,
        types: [{
          description: 'LPS and friends',
          accept: { 'text/plain': ['.lps', '.pl', '.lpsw', '.le', '.P', '.pddl', '.drl'] },
        }],
      });
      for (const h of hs) {
        const f = await h.getFile();
        const t = await loadPossiblyForeign(await f.text(), f.name);
        if (t && !/\.(pddl|drl)$/i.test(f.name)) { t.handle = h; state.fileHandle = h; }
      }
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
    state.dirty = false; syncToTab(); tabs.renderTabs(); setStatus('saved');
    return;
  }
  if (window.showSaveFilePicker) {
    try {
      const h = await window.showSaveFilePicker({ suggestedName: state.fileName });
      const w = await h.createWritable();
      await w.write(text); await w.close();
      state.fileHandle = h; state.fileName = h.name;
      const t = tabs.activeTab(); if (t) t.name = h.name;
      state.dirty = false; syncToTab(); tabs.renderTabs(); setStatus('saved');
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
  //  The 3D pane bakes its labels into canvas textures, so a theme switch has
  //  to redraw the scene or they keep the old ink.
  refreshPane();
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
      { label: 'New', run: () => tabs.openTab('maxTime(10).\n\n', 'untitled.lps') },
      { label: 'Open…', run: fileOpen },
      { label: 'Open example from server…', run: openExamples },
      '-',
      { label: 'Save', run: () => fileSave(false) },
      { label: 'Save As…', run: () => fileSave(true) },
      '-',
      { label: 'Close file', run: () => tabs.closeTab(tabs.activeTab()?.id) },
      '-',
      { label: 'Copy share link', run: copyShareLink },
    ]),
    menu('Edit', [
      { label: 'Undo', run: () => ed().trigger('menu', 'undo') },
      { label: 'Redo', run: () => ed().trigger('menu', 'redo') },
      '-',
      { label: 'Find', run: () => ed().trigger('menu', 'actions.find') },
      { label: 'Replace', run: () => ed().trigger('menu', 'editor.action.startFindReplaceAction') },
      { label: 'Go to line…', run: () => ed().trigger('menu', 'editor.action.gotoLine') },
      '-',
      { label: 'Toggle line comment', run: () => ed().trigger('menu', 'editor.action.commentLine') },
      { label: 'Toggle block comment', run: () => ed().trigger('menu', 'editor.action.blockComment') },
      '-',
      { label: 'Collapse all clauses', run: foldAllClauses },
      { label: 'Expand all', run: () => ed().trigger('menu', 'editor.unfoldAll') },
      '-',
      { label: 'Next problem (F8)', run: () => ed().trigger('menu', 'editor.action.marker.next') },
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
      { label: 'API keys, models & Assistant settings…', run: () => window.dispatchEvent(new Event('lps-open-settings')) },
      { label: 'Server token…', run: openTokenDialog },
      '-',
      { label: 'Deploy as WASM…', run: () => window.dispatchEvent(new Event('lps-deploy-wasm')) },
    ]),
    menu('Help', [
      { label: 'Using the IDE', href: '/docs/UsingTheIDE' },
      { label: 'Tutorial', href: '/docs/lps_tutorial' },
      { label: 'Language reference', href: '/docs/lps_summary' },
      { label: 'Introducing LPS2', href: '/docs/IntroducingLPS2' },
      '-',
      { label: 'About the icons used in animations…', run: showIcons },
      { label: 'About LPS2…', run: showAbout },
    ]),
  );
}

/*  "Collapse all" used to call `editor.foldAll`, which folds Monaco's own
 *  ranges — and Monaco's ranges come from indentation, which a Prolog file
 *  mostly does not have. So it appeared to do nothing. Folding *clauses* is
 *  what was meant: fold every region that starts on a clause head. */
function foldAllClauses() {
  const ed = state.editor, model = ed.getModel();
  const lines = [];
  const head = /^[a-z'][^%]*?(\(|\s)/;
  const text = model.getLinesContent();
  text.forEach((l, i) => {
    if (!head.test(l)) return;
    //  A clause worth folding spans more than one line.
    let j = i;
    while (j < text.length && !/\.\s*(%.*)?$/.test(text[j])) j++;
    if (j > i) lines.push(i + 1);
  });
  if (!lines.length) { ed.trigger('menu', 'editor.foldAll'); setStatus('nothing multi-line to fold'); return; }
  ed.trigger('lps', 'editor.fold', { selectionLines: lines });
  setStatus(`folded ${lines.length} clause(s)`);
}

function openTokenDialog() {
  const inp = el('input', { type: 'password', value: api.getToken(), placeholder: 'LPS_TOKEN' });
  openDialog('Server token', el('div', {}, el('p', { text: 'Required when the server was started with LPS_TOKEN set.' }), inp), [
    el('button', { text: 'Cancel', onclick: closeDialog }),
    el('button', { class: 'primary', text: 'Save', onclick: () => { api.setToken(inp.value); closeDialog(); } }),
  ]);
}

async function showIcons() {
  const body = el('div', { class: 'about' }, el('p', { class: 'empty', text: 'loading…' }));
  openDialog('The icons used in animations', body);
  try {
    const m = await fetch('/assets/icons/manifest.json').then((r) => r.json());
    const sets = m.sets || {};
    const names = Object.keys(m.icons || {}).sort();
    body.replaceChildren(
      el('p', {}, el('span', { text: 'A ' }), el('b', { text: `${names.length}-icon library` }),
        el('span', { text: ' is checked into this repository and served from this server, so a deployment with no internet still animates. Reach one from a program with ' }),
        el('code', { text: '[type:raster, icon:NAME]' }), el('span', { text: '.' })),
      el('p', { class: 'muted', text: 'The set was chosen by a functor census over the corpus — finance and contracts, legal and governance, puzzles and games, places and motion — so the names are the words a fluent or an action is likely to be called.' }),
      el('h4', { text: 'Where they come from' }),
      el('ul', {}, ...Object.entries(sets).map(([k, v]) =>
        el('li', {}, el('b', { text: k }), el('span', { text: ` — ${v.license}, ${v.attribution}` })))),
      el('h4', { text: `The names (${names.length})` }),
      el('div', { class: 'iconlist' }, ...names.map((n) => el('span', { class: 'icontag' },
        el('img', { src: `/assets/icons/${n}.svg`, alt: n, loading: 'lazy' }),
        el('code', { text: n })))));
  } catch (e) {
    body.replaceChildren(el('p', { text: 'The icon manifest could not be read: ' + e.message }));
  }
}

function showAbout() {
  openDialog('LPS2', el('div', { class: 'about' },
    el('p', { text: 'A reimplementation of the LPS engine in SWI-Prolog, held to LPS1’s own corpus trace-for-trace.' }),
    el('p', {}, el('span', { text: 'Monaco, Konva, three.js and dagre are MIT. Icon licences are in ' }),
      el('b', { text: 'Help ▸ About the icons' }), el('span', { text: '.' })),
    el('p', { class: 'muted', text: 'Build ' + (window.LPS_BUILD || 'dev') })));
}

/* ---- splitters ----------------------------------------------------------- */

function makeSplitter() {
  const sp = $('splitter'), root = $('workbench');
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

/*  The left column is a grid of [tabs, editor, grip, assistant, grip, live].
 *  Both docks are resizable, and remember their height — an assistant you have
 *  to scroll to read is an assistant you stop reading. */
function makeDockSplitters() {
  const left = $('left');
  const sizes = { assistant: store.get('h.assistant', 220), live: store.get('h.live', 220) };
  const apply = () => {
    const a = $('assistant').classList.contains('collapsed') ? 0 : sizes.assistant;
    const l = $('live').classList.contains('collapsed') ? 0 : sizes.live;
    left.style.gridTemplateRows = `auto 1fr 4px ${a ? a + 'px' : 'auto'} 4px ${l ? l + 'px' : 'auto'}`;
  };
  apply();
  window.addEventListener('lps-dock', apply);
  for (const which of ['assistant', 'live']) {
    const grip = $('hsplit-' + which);
    let from = null;
    grip.addEventListener('pointerdown', (e) => {
      if ($(which).classList.contains('collapsed')) return;
      from = { y: e.clientY, h: sizes[which] };
      grip.setPointerCapture(e.pointerId); document.body.classList.add('dragging');
    });
    grip.addEventListener('pointermove', (e) => {
      if (!from) return;
      sizes[which] = Math.max(80, Math.min(window.innerHeight - 220, from.h + (from.y - e.clientY)));
      store.set('h.' + which, sizes[which]);
      apply();
    });
    const stop = (e) => {
      if (!from) return;
      from = null; document.body.classList.remove('dragging');
      try { grip.releasePointerCapture(e.pointerId); } catch { /* gone */ }
    };
    grip.addEventListener('pointerup', stop);
    grip.addEventListener('pointercancel', stop);
  }
}

/* ---- status -------------------------------------------------------------- */

export function setStatus(msg) {
  const s = $('status');
  s.textContent = msg;
  s.classList.remove('has-errors', 'has-warnings');
}

/* ---- boot ---------------------------------------------------------------- */

async function boot() {
  makeEditor();
  buildMenus();
  makeSplitter();
  makeDockSplitters();

  $('tabs').replaceChildren(...PANES.map(([id, label]) => el('button', {
    'data-pane': id, text: label, onclick: () => { selectPane(id); refreshPane(); },
  })));
  selectPane(state.pane);

  initWhy({ state, api, openDialog, closeDialog, setStatus, renderExplanation });

  $('run').addEventListener('click', () => runProgram());
  $('status').addEventListener('click', () => state.editor.trigger('status', 'editor.action.marker.next'));
  $('cycle-slider').addEventListener('input', (e) => setCycle(Number(e.target.value)));
  $('file-input').addEventListener('change', async (e) => {
    for (const f of e.target.files) await loadPossiblyForeign(await f.text(), f.name);
  });
  for (const id of ['dfa-abstract', 'dfa-nonreflexive']) {
    $(id)?.addEventListener('change', () => refreshPane());
  }
  $('dialog-close').addEventListener('click', closeDialog);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeDialog(); });

  /* "Deploy as WASM" (M11): the server bundles the engine's core sources and
   * this program into one page that runs in a browser with no server at all.
   * It opens in a new tab and can be saved. */
  window.addEventListener('lps-deploy-wasm', async () => {
    setStatus('bundling…');
    try {
      /*  An absolute runtime URL, not the server's default relative one: the
       *  page is opened from a `blob:` URL, and a relative script src there
       *  resolves against the blob's own opaque origin. That is what made
       *  "Open" fail with `Can't find variable: SWIPL`. */
      const runtime = new URL('/assets/swipl/swipl-web.js', location.origin).toString();
      const r = await api.api({
        operation: 'wasm_bundle', source: state.editor.getValue(),
        title: state.fileName, runtime,
      });
      const blob = new Blob([r.html], { type: 'text/html' });
      const url = URL.createObjectURL(blob);
      const kb = Math.round(r.html.length / 1024);
      openDialog('Deploy as WASM',
        el('div', {},
          el('p', { text: `${state.fileName} and the LPS2 engine, in one page of ${kb} kB. It runs in the browser with no server of its own: the core is pure Prolog with no threads, sockets, clock or file I/O, which is the property tools/lint_core.pl has been enforcing since M1.` }),
          el('p', {}, el('b', { text: 'The page still fetches the SWI-Prolog WebAssembly runtime' }),
            el('span', { text: ` from ${runtime}. Open it from here and it works while this server is running; save it and it keeps working from anywhere that can reach that URL.` })),
          el('p', { class: 'muted', text: 'To make it self-contained, put a copy of this server’s /assets/swipl/ directory beside the saved page and change the one <script src> at the top to "swipl/swipl-web.js". A .wasm file will not load over file://, so serve the directory:' }),
          el('pre', { class: 'code', text: 'python3 -m http.server 8000        # macOS, Linux\npy -m http.server 8000             # Windows\nnpx serve .                        # anywhere with Node\n\nthen open http://localhost:8000/your-page.html' })),
        [
          el('button', { text: 'Close', onclick: closeDialog }),
          el('a', { class: 'item', href: url, download: state.fileName.replace(/\.\w+$/, '') + '-wasm.html', text: 'Download' }),
          el('button', { class: 'primary', text: 'Open', onclick: () => { window.open(url, '_blank'); closeDialog(); } }),
        ]);
      setStatus('bundled');
    } catch (e) { setStatus('bundle failed: ' + e.message); }
  });

  mountAssistant({ state, api, setStatus, openDialog, closeDialog, el });
  mountLive({ state, api, setStatus, el, refreshPane, setCycle });

  /* A handle for the browser tests and the documentation's screenshot script.
   * Monaco is bundled, so `window.monaco` does not exist; without this a test
   * cannot put a program in the editor. */
  window.LPS = {
    state, api, monaco, tabs, load: loadSource, run: runProgram,
    pane: selectPane, refresh: refreshPane, setCycle, why: openWhy,
  };

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

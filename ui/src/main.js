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
import { registerLps, LANGUAGE_ID, setVocabulary, vocabulary } from './lps-language.js';
import { registerLe, LE_LANGUAGE_ID, templateCompletions } from './le-language.js';
import * as api from './api.js';
import { el, empty, renderTimeline, renderChanges, renderExplanation, renderInternal, renderGenerated } from './panes/basic.js';
import { renderAutomaton } from './panes/automaton.js';
import { renderScene2d } from './panes/scene2d.js';
import { wireMouse } from './panes/mouse.js';
import { renderScene3d } from './panes/scene3d.js';
import { mountAssistant } from './assistant.js';
import { mountLive } from './live.js';
import { mountPlay } from './play.js';
import * as tabs from './tabs.js';
import { initWhy, wireWhy, openWhy } from './why.js';
import { icons as ICONS, licenses as ICON_LICENSES, iconUrl } from './icons.js';

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
  state.lastRun = t.lastRun || null;
  state.le = t.le || null;
  if (tabs.syntaxOf(t.name) === 'le') { ensureLeMode(); checkLeAvailable(); }
  setCycleBounds();
  $('pane-program').textContent = t.name;
  window.dispatchEvent(new CustomEvent('lps-profile', { detail: t.profile }));
  //  The toolbar's maxTime shows the program's own, as a starting point. A
  //  different file is a different program, so a value typed for the last one
  //  does not follow it here.
  const mt = $('max-time');
  delete mt.dataset.edited;
  mt.value = t.profile?.max_time ?? '';
  setStale(false);
  markPaneAvailability();
  syncPaneHeader();
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
    //  The editor's column clips its content — see style.css — so the widgets
    //  that are meant to escape it (suggest, hover, parameter hints) have to be
    //  told to hang themselves off the body instead of off the editor.
    fixedOverflowWidgets: true,
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
      //  The panes are now about a program that is not the one on screen.
      if (state.session && !state.live) setStale(true);
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
  /*  A Logical English document, or the `.lps` companion of one that is open:
   *  either way the thing to analyse is the pair, because that is the program
   *  (§7 of docs/le_lps_surface.md). */
  const pair = tabs.lePair();
  if (pair) return analyseLe(model, pair);
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
    decorateVocabulary();
    markPaneAvailability();
    //  The toolbar's maxTime is the program's own until somebody types over it.
    //  It was filled once, on tab switch, before the first analysis had come
    //  back — so at rest it showed the placeholder and looked like a setting
    //  nobody had made.
    const mt = $('max-time');
    if (mt && !mt.dataset.edited && state.profile?.max_time != null) {
      mt.value = state.profile.max_time;
    }
    window.dispatchEvent(new CustomEvent('lps-profile', { detail: state.profile }));
  } catch (e) {
    monaco.editor.setModelMarkers(model, 'lps', [{
      severity: monaco.MarkerSeverity.Error, message: e.message,
      startLineNumber: 1, startColumn: 1, endLineNumber: 1, endColumn: 2,
    }]);
    setProblemCount([{ severity: 'error' }]);
  }
}

/*  Fluents blue, events and actions amber — LPS1's own colours.
 *
 *  `legacy_lps1/swish/web/lps/lps.css` gave `.cm-fluent` a #D7DCF5 chip and
 *  `.cm-event`/`.cm-action` #E19735 text, and that is the colouring anyone who
 *  has used LPS on SWISH is expecting. It cannot come from the tokenizer: which
 *  names are fluents is in the declarations, not in the syntax. So it is a
 *  decoration pass, re-run whenever the analysis comes back — which is also
 *  what makes it *correct* as you type, since adding a name to `fluents` colours
 *  every use of it.
 *
 *  A name is matched as an identifier, not as a substring: `row` must not light
 *  up inside `narrow`, and a name inside a comment or a quoted atom is left
 *  alone. */
let vocabDecorations = [];
function decorateVocabulary() {
  const ed = state.editor, model = ed?.getModel();
  if (!model) return;
  const v = vocabulary();
  const kinds = [['fluent', v.fluents], ['event', v.events], ['action', v.actions]];
  const decs = [];
  const seen = new Set();
  for (const [kind, names] of kinds) {
    for (const name of names) {
      if (!name || seen.has(name)) continue;
      seen.add(name);
      const pat = `(?<![A-Za-z0-9_'\"])${name.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?![A-Za-z0-9_])`;
      let matches = [];
      try { matches = model.findMatches(pat, true, true, true, null, false); } catch { continue; }
      for (const m of matches) {
        if (inCommentOrQuote(model, m.range)) continue;
        decs.push({ range: m.range, options: { inlineClassName: 'lps-' + kind } });
      }
    }
  }
  vocabDecorations = ed.deltaDecorations(vocabDecorations, decs);
}

//  Cheap and local: everything after an unquoted % on the line is a comment,
//  and a name inside quotes is part of an atom, not a use of the predicate.
function inCommentOrQuote(model, range) {
  const line = model.getLineContent(range.startLineNumber);
  const before = line.slice(0, range.startColumn - 1);
  const pct = before.indexOf('%');
  if (pct >= 0 && (before.match(/'/g) || []).length % 2 === 0) return true;
  if ((before.match(/'/g) || []).length % 2 === 1) return true;
  if ((before.match(/"/g) || []).length % 2 === 1) return true;
  return false;
}

/*  Which clauses fired in the run just finished, in the gutter. A rule that
 *  never fires is the commonest bug in a first LPS program, and it is invisible:
 *  the program runs, it just does nothing. The trace names the law behind every
 *  state change (`src(File,Line,…)`), so the lines are known. */
let firedDecorations = [];
async function decorateFired() {
  const ed = state.editor, model = ed?.getModel();
  if (!model || !state.session) return;
  let lines = new Set();
  //  The same walk answers a second question — *which cycles* changed anything —
  //  and that is what the slider's tick marks and the changes pane's "the next
  //  one that changed" are made of. Asked once, not three times.
  const changed = [];
  try {
    const t = await api.timeline(state.session);
    const cycles = t.cycles || state.maxCycle;
    for (let c = 1; c <= cycles; c++) {
      const ch = await api.changes(state.session, c);
      let any = false;
      for (const g of ['initiated', 'terminated', 'updated']) {
        for (const x of (ch[g] || [])) {
          any = true;
          //  `src(buffer,24,0,internal)` — the line is the second argument.
          const m = /^src\([^,]*,\s*(\d+)/.exec(x.source || '');
          if (m) lines.add(Number(m[1]));
        }
      }
      if (any) changed.push(c);
    }
    const tab = tabs.activeTab();
    if (tab) tab.changedCycles = changed;
    drawCycleMarks();
    /*  A run in which nothing ever changed is not a broken pane, and the panes
     *  cannot tell the difference on their own: every cycle of `lights.lps` and
     *  `thermostat.lps` says "Nothing changed at cycle N" — correctly, because
     *  both wait for events that a batch run never sends. Say it once, here,
     *  where the whole run is in view, and point at the thing that would make
     *  something happen. */
    if (!changed.length && (state.profile?.events || []).length) {
      setStatus(state.lastRun + '  ·  nothing changed: this program waits for events — try Live session');
    }
  } catch { return; }
  firedDecorations = ed.deltaDecorations(firedDecorations, [...lines].map((l) => ({
    range: new monaco.Range(l, 1, l, 1),
    options: { isWholeLine: true, linesDecorationsClassName: 'lps-fired', glyphMarginHoverMessage: { value: 'this clause fired in the last run' } },
  })));
}

/*  A Logical English buffer is analysed by translating it.
 *
 *  There is no separate LE analyser and there should not be: the LE issues and
 *  the LPS diagnostics are the two halves of "is this a program", and the only
 *  way to get the second is to compile what the first produced. `le_compile`
 *  does both and returns them **concatenated, never merged** (§2 of the
 *  interface): they are different claims about different texts, and an editor
 *  that blended them could not say which half to trust when they disagree.
 *
 *  Markers land on the `.le` line, because every generated term carries the
 *  provenance of the sentence it came from — which is what M8a was for. */
async function analyseLe(model, pair) {
  const source = pair.le.model.getValue();
  try {
    const r = await api.api(leRequest('le_compile', pair));
    if (state.editor.getModel() !== model) return;         // the user switched tabs
    const all = [...(r.issues || []), ...(r.diagnostics || [])];
    placeLeMarkers(pair, all);
    setProblemCount(all);
    state.profile = r.profile || null;
    state.le = { lps: r.lps || '', provenance: r.provenance || [] };
    //  On the document, always: it is the half the generated program belongs
    //  to, and the Internal pane reads it from there whichever half is lit.
    pair.le.le = state.le;
    const t = tabs.activeTab();
    if (t) { t.le = state.le; t.profile = state.profile; }
    setVocabulary(state.profile);
    markPaneAvailability();
    window.dispatchEvent(new CustomEvent('lps-profile', { detail: state.profile }));
    if (state.pane === 'internal') refreshPane();
    loadLeTemplates(source);
  } catch (e) {
    monaco.editor.setModelMarkers(model, 'lps', [{
      severity: monaco.MarkerSeverity.Error, message: e.message,
      startLineNumber: 1, startColumn: 1, endLineNumber: 1, endColumn: 2,
    }]);
    setProblemCount([{ severity: 'error' }]);
  }
}

/*  The request that carries both halves of a Logical English program.
 *
 *  The companion goes as *text* rather than as a name: the browser has no file
 *  system for the server to look beside the document in, and the text in the
 *  tab is the version the user is editing rather than the one last saved. */
function leRequest(operation, pair) {
  const body = {
    operation, source: pair.le.model.getValue(), name: pair.le.name,
  };
  if (pair.lps) {
    body.companion = pair.lps.model.getValue();
    body.companion_name = pair.lps.name;
  }
  return body;
}

/*  A diagnostic belongs to the file it names.
 *
 *  Both halves compile as one program, so both halves' problems come back in
 *  one list — and putting a companion's error on that line number of the
 *  English is how an editor comes to squiggle a sentence that is perfectly
 *  correct. Every term of the companion carries its own file (lps_le.pl), so
 *  the split is by name. */
function placeLeMarkers(pair, all) {
  const cname = pair.lps?.name;
  const mine = cname ? all.filter((d) => d.source?.file !== cname) : all;
  monaco.editor.setModelMarkers(pair.le.model, 'lps',
    mine.map((d) => markerFor(d, pair.le.model)));
  if (pair.lps) {
    monaco.editor.setModelMarkers(pair.lps.model, 'lps',
      all.filter((d) => d.source?.file === cname).map((d) => markerFor(d, pair.lps.model)));
  }
}

function markerFor(d, model) {
  const line = Math.max(1, d.source?.line || 1), col = (d.source?.col || 0) + 1;
  return {
    severity: d.severity === 'error' ? monaco.MarkerSeverity.Error
      : d.severity === 'warning' ? monaco.MarkerSeverity.Warning
        : monaco.MarkerSeverity.Info,
    message: `${d.message}  [${d.code}]`,
    startLineNumber: line, startColumn: col,
    endLineNumber: line,
    endColumn: Math.max(col + 1, model.getLineMaxColumn(Math.min(line, model.getLineCount()))),
  };
}

/*  The templates a Logical English document declares, for completion. Asked
 *  for separately from the compile because it is the *language* view of the
 *  buffer rather than the program view, and because it survives a document
 *  that does not compile. */
let leTemplates = [];
async function loadLeTemplates(source) {
  try {
    const a = await api.api({ operation: 'le_analyse', source });
    leTemplates = a.templates || [];
  } catch { leTemplates = []; }
}

/*  The mode itself, built once from the server's lexicon — see le-language.js
 *  for why it is not a table in this repository. */
let leReady = null;
function ensureLeMode() {
  if (leReady) return leReady;
  leReady = api.api({ operation: 'le_lexicon', language: 'en' })
    .then((lex) => {
      registerLe(monaco, lex);
      monaco.languages.registerCompletionItemProvider(LE_LANGUAGE_ID, {
        provideCompletionItems: () => ({ suggestions: templateCompletions(monaco, leTemplates) }),
      });
      return true;
    })
    .catch(() => false);
  return leReady;
}

/*  Whether Logical English can be compiled at all, asked once and remembered.
 *  With no LE2 configured a `.le` file still *opens* — reading it is useful —
 *  but it says so, in the status line, rather than failing at the first run
 *  with a message about an environment variable. */
let leStatus = null;
function checkLeAvailable() {
  if (leStatus) return leStatus;
  leStatus = api.api({ operation: 'le_status' })
    .then((r) => {
      state.leAvailable = !!r.available;
      if (!r.available) setStatus(r.message || 'Logical English needs LE2');
      return r;
    })
    .catch(() => ({ available: false }));
  return leStatus;
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
    id: 'lps.runOne', label: 'Run one more cycle',
    keybindings: [K.CtrlCmd | C.Period],
    contextMenuGroupId: 'lps', contextMenuOrder: 0.5, run: () => runMore(1),
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
      //  A jump may have landed in another tab (an included resource).
      if (state.jumpBack.tab && tabs.activeTab()?.id !== state.jumpBack.tab) tabs.setActive(state.jumpBack.tab);
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
  const res = resourceAtCursor(ed);
  if (res) return openResource(res);
  const w = ed.getModel().getWordAtPosition(ed.getPosition());
  if (!w) return;
  const hits = clauseHeads(ed.getModel(), w.word);
  if (!hits.length) { setStatus(`no definition of ${w.word} in this file`); return; }
  state.jumpBack = { tab: tabs.activeTab()?.id, ...ed.getPosition() };
  ed.setPosition({ lineNumber: hits[0], column: 1 });
  ed.revealLineInCenter(hits[0]);
}

/*  "Show definition" on a Logical English `includes these resources:` line
 *  is a request to see the resource, which is a document, not a clause. The
 *  item under the cursor is what the line names — `world`, `../lib/rules.pl`,
 *  a URL — and the server resolves it the way the compiler does, against the
 *  same base (an untitled story on the IF library finds examples/if/). A
 *  local file opens in a tab, with its companion; a URL opens in a window. */
function resourceAtCursor(ed) {
  const model = ed.getModel(), pos = ed.getPosition();
  const line = model.getLineContent(pos.lineNumber);
  const m = /includes these resources\s*:/.exec(line);
  if (!m) return null;
  const from = m.index + m[0].length;
  let tail = line.slice(from).replace(/\s*\.\s*$/, '');
  let col = from;
  for (const raw of tail.split(',')) {
    const start = col, end = col + raw.length;
    col = end + 1;
    const item = raw.trim();
    if (!item) continue;
    if (pos.column - 1 >= start && pos.column - 1 <= end) return item;
  }
  return null;
}

async function openResource(item) {
  const t = tabs.activeTab();
  setStatus(`resolving ${item}…`);
  let r;
  try { r = await api.resource(t?.name || '', state.editor.getValue(), item); }
  catch (e) { setStatus(e.message); return; }
  if (r.kind === 'url') { window.open(r.url, '_blank', 'noopener'); setStatus(`opened ${r.url}`); return; }
  state.jumpBack = { tab: t?.id, ...state.editor.getPosition() };
  const have = tabs.tabNamed(r.name);
  if (have) { tabs.setActive(have.id); setStatus(`${r.name} was already open`); return; }
  tabs.openTab(r.source, r.name);
  openCompanion(r);
  setStatus(`opened ${r.path || r.name}`);
}

/*  Occurrences of the *name*, not of the string.
 *
 *  A substring search for `row` in the goat finds `row(south,north)` and also
 *  `narrow`, `borrow` and the word inside a comment about arrows. Monaco's
 *  findMatches takes a regular expression, so ask for the identifier: the name
 *  bounded by something that cannot be part of one. */
function showOccurrences(ed) {
  const w = ed.getModel().getWordAtPosition(ed.getPosition());
  if (!w) return;
  const pat = `(?<![A-Za-z0-9_])${w.word.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}(?![A-Za-z0-9_])`;
  const matches = ed.getModel().findMatches(pat, true, true, true, null, false);
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

/*  A `maxTime` typed in the toolbar wins over the one in the file, for this run
 *  only — the buffer is not edited. Lengthening a run to see what happens next
 *  is the commonest thing a reader wants and it should not mean an edit and an
 *  undo. */
function sourceForRun() {
  const source = state.editor.getValue();
  const n = Number($('max-time').value);
  if (!Number.isFinite(n) || n <= 0) return source;
  const stripped = source.replace(/^\s*maxTime\s*\(\s*\d+\s*\)\s*\.\s*$/gm, '');
  return `maxTime(${n}).\n` + stripped;
}

/*  The program in the active tab, compiled as what it is.
 *
 *  Either half of a Logical English program is the whole of it: the companion
 *  on its own is a set of display clauses, and running *that* draws nothing at
 *  all. Anything else compiles in the syntax its name says. Run and Live share
 *  this; Live used to compile the buffer as legacy LPS whatever the tab held,
 *  and a Logical English story answered "syntax error: operator_expected
 *  (line 1)" — the first line of English read as Prolog. */
async function compileCurrent(source) {
  const pair = tabs.lePair();
  if (pair) return compileLe(pair);
  return api.compile(source ?? state.editor.getValue(), tabs.syntaxOf(state.fileName));
}

async function runProgram(cycles) {
  setStatus('compiling…');
  try {
    const c = await compileCurrent(sourceForRun());
    state.program = c.program;
    const s = await api.sessionNew(c.program);
    state.session = s.session;
    //  The previous run's landmarks are not this run's. Cleared here rather
    //  than left to be overwritten, so nothing between here and decorateFired
    //  can read them as current.
    { const t0 = tabs.activeTab(); if (t0) delete t0.changedCycles; }
    setStatus('running…');
    const r = await api.run(state.session, cycles);
    /*  Land on the last cycle *that has a state*.
     *
     *  Two traps here. Cycle 0 is the initial state and cycle 1 is usually
     *  still empty, so opening at the start meant "Nothing changed at cycle 1"
     *  and a drag to find the interesting part. But the engine's final clock
     *  reading is one past the last recorded cycle — `lights.lps` reports 21
     *  cycles and has no fluents at 21 — so landing on *that* shows an empty
     *  scene. The timeline knows which cycles were actually recorded. */
    let last = r.cycle;
    try { const t = await api.timeline(state.session); if (t.cycles) last = t.cycles; } catch { /* keep the clock's answer */ }
    state.maxCycle = last;
    state.cycle = last;
    state.lastRun = describeRun(r);
    setStatus(state.lastRun);
    { const t0 = tabs.activeTab(); if (t0) { t0.lastRun = state.lastRun; t0.runs = (t0.runs || 0) + 1; } }
    rememberRun(r);
    setCycleBounds();
    syncToTab();
    tabs.renderTabs();
    markPaneAvailability();
    setStale(false);
    await refreshPane();
    decorateFired();
    window.dispatchEvent(new CustomEvent('lps-ran', { detail: state }));
    if (r.status !== 'success') jumpToTrouble();
  } catch (e) {
    if (!reportApiError(e, 'the run', () => runProgram(cycles))) {
      /*  A run that was refused has to *say so*, and used to not.
       *
       *  `analyseNow` ends by writing the problem count over the status line,
       *  so pressing Run on a program with a syntax error left "1 error, 1
       *  warning" — the same words as before the click, with the previous
       *  program's results still in every pane. From the outside, Run did
       *  nothing at all. The analysis still runs (the squiggles are the useful
       *  part); it just no longer gets the last word. */
      const why = e.message || 'it did not compile';
      await analyseNow();
      setStatus(`not run — ${why}`, 'has-errors');
      jumpToFirstProblem();
    }
  }
}

/*  The panes are showing a run of a program that is no longer in the editor.
 *  Everything on the right is a reading of a trace, and a trace belongs to the
 *  text it came from; without this the viewport quietly presents an older
 *  program's answers as this one's. */
function setStale(on) {
  document.getElementById('right')?.classList.toggle('stale', !!on);
  const tag = $('pane-stale');
  if (tag) tag.style.display = on ? '' : 'none';
}

function jumpToFirstProblem() {
  try { state.editor.trigger('run', 'editor.action.marker.next'); } catch { /* no markers */ }
}

/*  Compiling a Logical English document: the same operation the analysis uses,
 *  so a run cannot disagree with the squiggles. It throws with the first error
 *  message rather than returning a program id nobody can use. */
async function compileLe(pair) {
  const r = await api.api(leRequest('le_compile', pair));
  state.le = { lps: r.lps || '', provenance: r.provenance || [] };
  pair.le.le = state.le;
  const t = tabs.activeTab(); if (t) t.le = state.le;
  if (r.program) return r;
  const all = [...(r.issues || []), ...(r.diagnostics || [])];
  const first = all.find((d) => d.severity === 'error') || all[0];
  throw new Error(first ? `${first.message}` : 'Logical English did not compile');
}

//  "success after 21 cycles" says how far it got, not why it stopped there;
//  a run that hit maxTime and one that ran out of things to do both say
//  "success" and only one of them is finished.
function describeRun(r) {
  const secs = r.ms == null ? '' : `  ·  ${r.ms < 1000 ? r.ms + ' ms' : (r.ms / 1000).toFixed(1) + ' s'}`;
  return `${r.status} after ${r.cycle} cycles${r.reason ? '  ·  ' + r.reason : ''}${secs}`;
}

/*  A run that did not succeed is a run with a first bad cycle, and finding it
 *  by dragging is the slow way. Land on it, in the pane that shows changes. */
async function jumpToTrouble() {
  try {
    const t = await api.timeline(state.session);
    const last = Math.max(0, (t.cycles || state.maxCycle) - 0);
    setCycle(last);
    setStatus(state.lastRun + '  ·  showing the last cycle it reached');
  } catch { /* the status already says what happened */ }
}

/*  The previous run of this file, kept so two runs can be compared. Only the
 *  trace is kept, not the session: comparing is a read. */
function rememberRun(r) {
  const t = tabs.activeTab();
  if (!t) return;
  t.prevRun = t.thisRun || null;
  t.thisRun = { session: state.session, cycle: r.cycle, status: r.status, at: Date.now() };
}

function setCycleBounds() {
  $('cycle-slider').max = String(state.maxCycle);
  $('cycle-slider').value = String(state.cycle);
  $('cycle-label').textContent = `cycle ${state.cycle}`;
  drawCycleMarks();
  syncPaneHeader();
}

/*  Landmarks on the slider: a tick under every cycle in which something
 *  changed. Scrubbing a twenty-cycle run to find the four interesting ones is
 *  otherwise a hunt, and the pane you land in mostly says "Nothing changed at
 *  cycle N", which reads like a broken pane rather than like a quiet cycle.
 *  The set is collected by decorateFired, which already walks every cycle. */
function drawCycleMarks() {
  const host = $('cycle-marks');
  if (!host) return;
  const max = state.maxCycle || 0;
  const marks = (tabs.activeTab()?.changedCycles) || [];
  if (!max || !marks.length) { host.replaceChildren(); return; }
  host.replaceChildren(...marks.filter((c) => c <= max).map((c) => {
    const m = document.createElement('i');
    //  The thumb is 14 px wide, so the track a value maps to is inset by half
    //  of it at each end; without that the last mark sits past the last cycle.
    m.style.left = `calc(7px + ${(c / max) * 100}% - ${(c / max) * 14}px)`;
    m.title = `cycle ${c} — something changed`;
    m.addEventListener('click', () => setCycle(c));
    return m;
  }));
}

/* ---- panes --------------------------------------------------------------- */

/*  Consistent case, and two names that are not near-homophones: "state changes"
 *  and "state transitions" sat next to each other and are a table of diffs and
 *  a state machine, which is not a distinction those two phrases carry. */
const PANES = [
  ['timeline', 'Timeline'],
  ['changes', 'Changes'],
  ['automaton', 'Automaton'],
  ['scene', '2D'],
  ['scene3d', '3D'],
  ['internal', 'Internal'],
];

//  Which section of the manual each pane is described in, for the `?` in the
//  pane header.
const PANE_HELP = {
  timeline: '/docs/UsingTheIDE#timeline',
  changes: '/docs/UsingTheIDE#changes',
  automaton: '/docs/UsingTheIDE#automaton',
  scene: '/docs/UsingTheIDE#2d',
  scene3d: '/docs/UsingTheIDE#3d',
  internal: '/docs/UsingTheIDE#internal',
};

function selectPane(id) {
  state.pane = id; store.set('pane', id);
  for (const b of document.querySelectorAll('#tabs button')) b.classList.toggle('on', b.dataset.pane === id);
  for (const p of document.querySelectorAll('.pane')) p.classList.toggle('on', p.id === 'pane-' + id);
  const h = $('pane-help');
  if (h) { h.href = PANE_HELP[id] || '/docs/UsingTheIDE'; h.title = `What the ${id} pane shows`; }
  markPaneAvailability();
  syncPaneHeader();
}

/*  The header carries controls that only some panes can act on, and it used to
 *  show all of them all the time: a transport, a slider reading "cycle 0" and
 *  "right-click anything to ask why it happened", stacked above the words "Run
 *  a program first" — three claims, two of them false. The internal-syntax pane
 *  is a static text dump and has neither cycles nor anything askable in it. */
const PANE_USES_CYCLES = { timeline: 1, changes: 1, automaton: 1, scene: 1, scene3d: 1 };
const PANE_IS_ASKABLE = { timeline: 1, changes: 1, automaton: 1, scene: 1, scene3d: 1 };

function syncPaneHeader() {
  const id = state.pane;
  const ran = !!state.session || !!state.live;
  const t = $('transport');
  //  A live session has no cycles to scrub: it is at whichever one it is at.
  if (t) t.style.display = (PANE_USES_CYCLES[id] && ran && !state.live) ? '' : 'none';
  const hint = $('pane-hint');
  if (hint) hint.style.display = (PANE_IS_ASKABLE[id] && ran) ? '' : 'none';
  const badge = $('pane-live');
  if (badge) badge.style.display = state.live ? '' : 'none';
}

/*  Which panes have something to show for *this* program, marked before the
 *  reader clicks through all six. 2D and 3D need display clauses; the rest need
 *  a run.
 *
 *  Two states, not one, and the difference matters: **waiting** ("run the
 *  program first") is about to become available and is worth nothing but a
 *  hint, while **empty** ("this program declares no display/2") will not change
 *  however many times you press Run. They used to share one grey and one
 *  tooltip.
 *
 *  And it must be called when the *facts* change, not when a tab is clicked.
 *  It was wired only to selectPane, so after a successful run every tab still
 *  read "run the program first" at 45% opacity — including `timeline`, which
 *  was drawing a timeline at that moment — until you visited it. The whole
 *  strip told a new user that nothing worked, precisely when everything did.
 */
export function markPaneAvailability() {
  const p = state.profile;
  const ran = !!state.session || !!state.live;
  for (const b of document.querySelectorAll('#tabs button')) {
    const id = b.dataset.pane;
    let why = '', cls = '';
    if (id === 'scene' || id === 'scene3d') {
      const decl = id === 'scene3d' ? 'display3d' : 'display';
      if (p && !p[decl]) {
        why = `this program declares no ${decl}/2 clauses — the pane offers to write them`;
        cls = 'empty-pane';
      } else if (!ran) { why = 'run the program first'; cls = 'waiting'; }
    } else if (id !== 'internal' && !ran) {
      why = 'run the program first'; cls = 'waiting';
    }
    b.classList.toggle('waiting', cls === 'waiting');
    b.classList.toggle('empty-pane', cls === 'empty-pane');
    b.classList.toggle('unavailable', !!why);
    b.title = why || `${b.textContent} for ${state.fileName}`;
  }
}

/*  The right-hand side before anything has been run. It is the largest empty
 *  area on the screen and the first thing a new reader looks at, so it says
 *  what to do rather than what has not been done — and each step carries the
 *  control that performs it, so nothing has to be found first.
 *
 *  Step one changes depending on whether a program is already open: telling
 *  somebody to open a file they have open is how a set of instructions loses
 *  its reader. */
/*  A live session is running, and this pane has nothing of its own to show.
 *  Saying "nothing has been run yet" here is false and reads as a fault: the
 *  header says LIVE at the same moment. Only the two scene panes follow a
 *  session; the rest are readings of a finished run. */
function nothingForLiveSession(pane) {
  pane.replaceChildren(el('div', { class: 'start-here' },
    el('h2', { text: 'A live session is running' }),
    el('p', { text: 'This pane reads a finished run, and there is not one.' }),
    el('ol', {},
      el('li', {}, el('div', { class: 'what', text: 'What the session is doing is in the Live panel, below the editor.' })),
      el('li', {}, el('div', { class: 'what', text: 'The 2D and 3D panes follow the session as it goes.' })),
      el('li', {},
        el('div', { class: 'what', text: 'Stop the session and press Run for a timeline of a fixed number of cycles.' })))));
}

function startHere(pane) {
  if (state.live) return nothingForLiveSession(pane);
  const hasText = !!state.editor?.getValue().trim();
  const step = (what, control, why) => {
    const li = el('li', {}, el('div', { class: 'what', text: what }));
    if (control) li.appendChild(control);
    if (why) li.appendChild(el('p', { class: 'why', text: why }));
    return li;
  };
  const button = (label, onclick, keys) => {
    const wrap = el('div', {}, el('button', { class: 'primary', text: label, onclick }));
    if (keys) wrap.appendChild(el('span', { class: 'keys', text: keys }));
    return wrap;
  };

  /*  A story — a Logical English document that includes the interactive-
   *  fiction library — can be run (it replays its own scenario) or played,
   *  and playing is the point of it. */
  const playPanel = window.LPS?.play;
  const story = !!playPanel?.isStory?.();
  const playStep = story
    ? [step('Or play it.',
        button('Play', () => playPanel.open()),
        'This document is a story: it includes the interactive-fiction library. '
        + 'Play opens the play panel below the editor and starts the story; type what '
        + 'a player types, or press Commands to see what would work. Run, instead, '
        + 'replays the scenario written in the document.')]
    : [];
  pane.replaceChildren(el('div', { class: 'start-here' },
    el('h2', { text: 'Nothing has been run yet' }),
    el('p', { text: story ? 'Three steps, or two. The results appear here.' : 'Three steps. The results of the run appear here.' }),
    el('ol', {},
      hasText
        ? step('You have a program open in the editor on the left.',
          button('Open a different example', openExamples),
          'File ▸ Open example from server, or File ▸ Open, do the same thing.')
        : step('Open a program.',
          button('Browse the examples', openExamples),
          'There are about a hundred, from a three-line thermostat to the wolf, '
          + 'goat and cabbage puzzle. File ▸ Open opens one of your own.'),
      step('Run it.',
        button('Run', () => runProgram(), 'or Ctrl/Cmd + Enter'),
        'The program runs a fixed number of cycles, which the tab above sets. '
        + 'Ctrl/Cmd + . runs one cycle more than last time.'),
      ...playStep,
      step('Read what happened.', null,
        'Timeline shows which facts were true in which cycles and which events '
        + 'occurred. Changes lists what each cycle started and stopped. 2D draws '
        + 'the state, for a program that says how it should be drawn. And a '
        + 'right-click on anything in those panes asks why it happened.'))));
}

async function refreshPane() {
  const pane = $('pane-' + state.pane);
  if (!pane) return;
  wireWhy(pane);
  if (state.pane === 'internal') {
    /*  For a Logical English document this pane is the *generated* program,
     *  and every line of it knows which English sentence produced it. That
     *  makes the two texts navigable in both directions, which is the most
     *  convincing thing about compiling English: you can point at a term and
     *  see the sentence that asked for it. */
    if (tabs.syntaxOf(state.fileName) === 'le' && state.le?.lps) {
      return renderGenerated(pane, state.le, (line) => goToLine(line));
    }
    if (!state.program) return startHere(pane);
    const d = await api.dump(state.program);
    return renderInternal(pane, d.dump, (name) => findInSource(name));
  }
  if (!state.session) return startHere(pane);
  try {
    switch (state.pane) {
      case 'timeline': {
        const t = await api.timeline(state.session);
        return renderTimeline(pane, t, state.cycle, (c) => setCycle(c));
      }
      case 'changes': {
        const c = await api.changes(state.session, Math.max(1, state.cycle));
        const empty = !(c.initiated?.length || c.terminated?.length || c.updated?.length);
        /*  Both directions, not only forward. After a run the panes land on the
         *  *last* cycle, which for `goat_declarative` is one of the four in
         *  which nothing happens — so the first thing the pane ever said was
         *  "Nothing changed at cycle 10", with a forward link to nowhere. */
        const near = empty ? nearestChangedCycles(state.cycle) : { prev: null, next: null };
        /*  `changedCycles` is filled by decorateFired, which runs *after* the
         *  first refresh of a run — so an empty array and "not walked yet" are
         *  different states, and treating them alike would tell the reader that
         *  nothing ever changed one beat before the ticks appeared saying it
         *  had. Only an array that exists is an answer. */
        const walked = tabs.activeTab()?.changedCycles;
        return renderChanges(pane, c, state.cycle, (n) => setCycle(n), near, goToLine,
          Array.isArray(walked) && walked.length === 0);
      }
      case 'automaton': {
        const a = await api.automaton(state.session, {
          abstract_numbers: $('dfa-abstract')?.checked || false,
          non_reflexive: $('dfa-nonreflexive')?.checked || false,
        });
        return renderAutomaton(pane, a, { onSeek: (c) => setCycle(c) });
      }
      /*  While a live session is running, these panes follow *it*.
       *
       *  They used to keep showing the last batch run — so a session ticking
       *  along at cycle 13 was watched through a picture of cycle 1 of
       *  something else, with nothing on screen to say so. The live scene is
       *  the same shape, so the renderers do not know the difference. */
      case 'scene': {
        const s = state.live
          ? await api.api({ operation: 'live_scene', live: state.live, kind: '2d' })
          : await api.scene(state.session, state.cycle);
        const r = renderScene2d(pane, s, s.cycle ?? state.cycle);
        liveMouse(pane, s, '2d');
        return r;
      }
      case 'scene3d': {
        const s = state.live
          ? await api.api({ operation: 'live_scene', live: state.live, kind: '3d' })
          : await api.scene3d(state.session, state.cycle);
        const r = renderScene3d(pane, s, s.cycle ?? state.cycle);
        liveMouse(pane, s, '3d');
        return r;
      }
    }
  } catch (e) {
    empty(pane, e.message);
  }
}

/*  The nearest cycle either side of this one in which anything changed — so an
 *  empty "state changes" pane can point at an interesting one instead of
 *  shrugging. Read from the set decorateFired collected, so it costs nothing:
 *  the previous version asked the server once per cycle, forward only, every
 *  time you landed on a quiet cycle. */
function nearestChangedCycles(from) {
  const all = tabs.activeTab()?.changedCycles || [];
  const prev = all.filter((c) => c < from).pop() ?? null;
  const next = all.find((c) => c > from) ?? null;
  return { prev, next };
}

export function goToLine(line) {
  const ed = state.editor;
  ed.revealLineInCenter(line);
  //  Select the whole clause, not just the line: a causal law is often three
  //  lines and the reader wants to see which one they landed in.
  const model = ed.getModel();
  let end = line;
  while (end < model.getLineCount() && !/\.\s*(%.*)?$/.test(model.getLineContent(end))) end++;
  ed.setSelection({ startLineNumber: line, startColumn: 1, endLineNumber: end, endColumn: model.getLineMaxColumn(end) });
  ed.focus();
}

function findInSource(name) {
  const ed = state.editor;
  const lines = clauseHeads(ed.getModel(), name);
  if (!lines.length) { setStatus(`no clause for ${name} in this buffer`); return; }
  goToLine(lines[0]);
}

/*  Clicks in the pane, sent to the live session — the same wiring the pop-out
 *  window has. Attached once per pane per session, and detached when the
 *  session ends, so a finished run's picture stops pretending to be live. */
const mouseOff = { scene: null, scene3d: null };
function liveMouse(pane, sceneReply, kind) {
  const key = kind === '3d' ? 'scene3d' : 'scene';
  const kinds = state.live ? (sceneReply.mouse || []) : [];
  if (mouseOff[key]) { mouseOff[key](); mouseOff[key] = null; }
  if (!kinds.length) return;
  mouseOff[key] = wireMouse(pane, {
    api: api.api, live: state.live, kind, mouseKinds: kinds,
    onNote: (m) => setStatus(m),
  });
  pane.title = 'click me — this program handles '
    + kinds.map((k) => k.replace('lps_mouse', '')).join('/');
}

function setCycle(c) {
  const max = Number($('cycle-slider').max) || 0;
  state.cycle = Math.max(0, Math.min(max, c));
  $('cycle-slider').value = String(state.cycle);
  $('cycle-label').textContent = `cycle ${state.cycle}`;
  //  Whoever follows the cycle — the play panel marks the turn it fell in.
  window.dispatchEvent(new CustomEvent('lps-cycle', { detail: state.cycle }));
  syncToTab();
  refreshPane();
}

/*  Walking the cycles. The slider is the *display*; these are the controls,
 *  because reading a trace is stepping and a slider is dragging. Play is a
 *  timer over the same setCycle. */
let playTimer = null;
function stepCycle(d) { setCycle(state.cycle + d); }
function playCycles() {
  if (playTimer) return stopPlaying();
  if (state.cycle >= state.maxCycle) setCycle(0);
  $('cycle-play').textContent = '⏸';
  $('cycle-play').title = 'Pause';
  playTimer = setInterval(() => {
    if (state.cycle >= state.maxCycle) return stopPlaying();
    setCycle(state.cycle + 1);
  }, 700);
}
function stopPlaying() {
  clearInterval(playTimer); playTimer = null;
  $('cycle-play').textContent = '▶';
  $('cycle-play').title = 'Play through the cycles (space)';
}

/* ---- menus, files, dialogs ------------------------------------------------ */

function openDialog(title, body, actions) {
  $('dialog-title').textContent = title;
  $('dialog-body').replaceChildren(body);
  $('dialog-actions').replaceChildren(...(actions || [el('button', { text: 'Close', onclick: closeDialog })]));
  $('dialog').classList.add('on');
}
export function closeDialog() { $('dialog').classList.remove('on'); }

/*  The example picker, as a tree.
 *
 *  It used to be one flat list of two hundred names, which is a list you scroll
 *  rather than read. The landing page at `/` groups them by directory and
 *  remembers which folders you had open; this does the same, from the same
 *  `dirpath` the server now reports, so the two cannot disagree. Typing filters
 *  across the whole tree and opens whatever matches; the arrows walk the
 *  matches and Enter opens one, so the keyboard alone is enough.
 */
async function openExamples() {
  const body = el('div', { class: 'examples' }, el('p', { class: 'empty', text: 'loading…' }));
  openDialog('Open example from server', body);
  let r;
  try {
    r = await api.listExamples();
  } catch (e) {
    /*  This used to be an unhandled rejection: the dialog sat on "loading…"
        for ever while the console carried the only account of what happened. */
    body.replaceChildren(el('p', { class: 'empty', text: e.message }));
    if (e.unauthorised) {
      const b = el('button', { class: 'primary', text: 'Enter the server token' });
      b.addEventListener('click', () => openTokenDialog(
        'This server was started with LPS_TOKEN set, so the example list was refused.',
        openExamples));
      body.appendChild(el('div', { class: 'empty-actions' }, b));
    }
    return;
  }

  const filter = el('input', {
    class: 'filter',
    placeholder: 'filter — type any part of a name or description',
    value: store.get('exFilter', ''),
  });
  const list = el('div', { class: 'list cols' });
  const preview = el('pre', { class: 'ex-preview muted', text: '' });
  let rows = [], sel = -1;

  const openIt = async (x) => {
    let e;
    try { e = await api.example(x.name); }
    catch (err) { reportApiError(err, `opening ${x.name}`, () => openIt(x)); return; }
    loadSource(e.source, e.name.split('/').pop(),
      e.converted_from ? { origin: e.converted_from, original: e.original } : undefined);
    openCompanion(e);
    if (e.diagnostics?.length) {
      setStatus(`${e.name}: ${e.diagnostics.length} conversion note(s) — see the comments`);
    }
    closeDialog();
  };

  const showPreview = async (x) => {
    preview.textContent = 'loading…';
    try {
      const e = await api.example(x.name);
      preview.textContent = e.source.split('\n').slice(0, 40).join('\n');
    } catch (err) { preview.textContent = err.message; }
  };

  const select = (i) => {
    if (!rows.length) return;
    sel = Math.max(0, Math.min(rows.length - 1, i));
    rows.forEach((row, j) => row.el.classList.toggle('sel', j === sel));
    rows[sel].el.scrollIntoView({ block: 'nearest' });
    showPreview(rows[sel].x);
  };

  const folderOpen = (dir) => store.get('exOpen.' + dir, dir === 'examples');
  const setFolderOpen = (dir, v) => store.set('exOpen.' + dir, v);

  /*  The directory names are this repository's, and this dialog is read by
   *  somebody who has never seen it: "corpus", "forTesting" and "CLOUT
   *  workshop" say nothing about what is inside them, and the counts (73, 63)
   *  are a reason not to open one. A sentence each. */
  const GROUP_BLURB = {
    'LPS2': 'written for LPS2 — the shortest way in',
    'corpus': 'the original LPS examples, run unchanged',
    'CLOUT workshop': 'contracts and smart-contract examples from the CLOUT workshop',
    'forTesting': 'small programs the engine is tested against — one idea each',
    'Kowalski book': 'from Kowalski’s book: logic, agents and the cycle',
    'PDDL': 'classical planning problems, converted on opening',
    'Drools': 'business rules, converted on opening',
    'Minecraft': 'an agent playing in a world it does not control',
    'simulation': 'programs that model something over time',
    'agent': 'programs that talk to a language model',
  };

  /*  A first visit does not want two hundred names. These five are the ones the
   *  documentation walks through, and between them they show each shape the IDE
   *  can draw: a plan, a tower, a picture you can click, and a program that
   *  never ends. */
  const START_HERE = [
    ['goat_declarative', 'a puzzle, stated rather than solved'],
    ['blocks', 'a tower rebuilt in reverse — and a 2D animation'],
    ['blocks3d', 'the same, in three dimensions'],
    ['lights', 'a picture you can click on (Live session)'],
    ['thermostat', 'a program that never ends, waiting for the world'],
  ];

  const draw = () => {
    const f = filter.value.toLowerCase().trim();
    store.set('exFilter', filter.value);
    const hits = r.examples.filter((x) => !f
      || x.name.toLowerCase().includes(f) || (x.title || '').toLowerCase().includes(f));
    //  Group by directory, in the order the server listed them.
    const groups = new Map();
    for (const x of hits) {
      const k = x.dirpath || x.dir || '';
      if (!groups.has(k)) groups.set(k, { label: x.dir || k, items: [] });
      groups.get(k).items.push(x);
    }
    rows = [];
    const out = [];
    //  Start here, above the tree and only when nothing is being searched for.
    if (!f) {
      out.push(el('div', { class: 'ex-folder open start-here', text: 'Start here' }));
      for (const [name, blurb] of START_HERE) {
        const x = r.examples.find((e) => e.name === name || e.name.endsWith('/' + name));
        if (!x) continue;
        const row = el('div', { class: 'row' },
          el('span', { class: 'ex-name', text: x.name }),
          el('span', { class: 'ex-title', text: blurb }));
        row.addEventListener('click', () => openIt(x));
        row.addEventListener('mouseenter', () => { sel = rows.findIndex((q) => q.el === row); });
        rows.push({ el: row, x });
        out.push(row);
      }
    }
    for (const [dir, g] of groups) {
      //  A filter is a search, and a search that hides its results behind a
      //  closed folder is not one: filtering opens everything that matched.
      const open = f ? true : folderOpen(dir);
      const head = el('div', { class: 'ex-folder' + (open ? ' open' : '') },
        el('span', { text: `${g.label}  (${g.items.length})` }),
        GROUP_BLURB[g.label] ? el('span', { class: 'ex-blurb', text: GROUP_BLURB[g.label] }) : null);
      head.addEventListener('click', () => { setFolderOpen(dir, !open); draw(); });
      out.push(head);
      if (!open) continue;
      for (const x of g.items) {
        const row = el('div', { class: 'row' },
          el('span', { class: 'ex-name', text: x.name }),
          el('span', { class: 'ex-title', text: x.title || '' }));
        row.addEventListener('click', () => openIt(x));
        row.addEventListener('mouseenter', () => { sel = rows.findIndex((q) => q.el === row); });
        rows.push({ el: row, x });
        out.push(row);
      }
    }
    list.replaceChildren(...out);
    if (rows.length && f) select(0);
  };

  filter.addEventListener('input', draw);
  filter.addEventListener('keydown', (e) => {
    if (e.key === 'ArrowDown') { select(sel + 1); e.preventDefault(); }
    else if (e.key === 'ArrowUp') { select(sel - 1); e.preventDefault(); }
    else if (e.key === 'Enter' && rows[sel]) { openIt(rows[sel].x); e.preventDefault(); }
  });

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
  body.replaceChildren(filter, el('div', { class: 'exwrap' }, list, grip), preview);
  draw();
  filter.focus();
  filter.select();
}

function loadSource(text, name, opts) {
  const t = tabs.openOrReuse(text, name || 'untitled.lps', opts);
  syncFromTab(t);
  return t;
}

/*  A Logical English example arrives with its `.lps` companion, and the
 *  companion gets a tab of its own — its own editor mode, its own diagnostics,
 *  its own place to be edited. It is not activated: the document is what was
 *  asked for.
 *
 *  Without this the IDE had half a program. `badlight.le` says in its own
 *  header that the picture lives in `badlight.lps`, and the 2D pane, seeing no
 *  `display/2` in the half it had, offered to write some — which is how an
 *  assistant came to append Prolog clauses to a document written in English. */
function openCompanion(e) {
  if (!e.companion || !e.companion_name) return null;
  if (tabs.tabNamed(e.companion_name)) return null;
  return tabs.openTab(e.companion, e.companion_name, { activate: false });
}

/*  PDDL and Drools are opened like any other file: the server converts them and
 *  hands back LPS with a header saying where it came from. §IV.4's point is
 *  that a front end is a *door*, not a fork, and the door should be the one
 *  everything else uses. */
/*  The other systems' files LE2's translators read (a Miniscript policy, a
 *  LegalRuleML or Daml file…): their extensions come from the server, once. */
let foreignExts = ['pddl', 'drl', 'sol'];
const foreignReady = api.api({ operation: 'import_formats' })
  .then((r) => {
    //  LPS2's own formats (a .pl is an LPS program here) stay LPS2's
    const own = ['txt', 'le', 'pl', 'lps', 'lpsw', 'p', 'pddl', 'drl'];
    for (const f of r.formats || []) for (const e of f.extensions) if (!own.includes(e.toLowerCase()) && !foreignExts.includes(e)) foreignExts.push(e);
    const input = document.getElementById('file-input');
    if (input && input.accept) input.accept = Array.from(new Set([...input.accept.split(','), ...foreignExts.map((e) => '.' + e)])).join(',');
  })
  .catch(() => {});
const isForeign = (name) => {
  const m = /\.([^.]+)$/.exec(name);
  return !!m && foreignExts.includes(m[1].toLowerCase());
};

async function loadPossiblyForeign(text, name) {
  await foreignReady;
  if (!isForeign(name)) return loadSource(text, name);
  setStatus(`converting ${name}…`);
  try {
    const r = await api.api({ operation: 'convert', source: text, name });
    if (r.diagnostics?.length) {
      setStatus(`${name}: ${r.diagnostics.length} conversion note(s) — see the comments`);
    } else setStatus(`converted ${name}`);
    return loadSource(r.source, r.name, { origin: name, original: text });
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
          accept: { 'text/plain': ['.lps', '.pl', '.lpsw', '.le', '.P', ...foreignExts.map((e) => '.' + e)] },
        }],
      });
      for (const h of hs) {
        const f = await h.getFile();
        const t = await loadPossiblyForeign(await f.text(), f.name);
        if (t && !isForeign(f.name)) { t.handle = h; state.fileHandle = h; }
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

/*  File > New. The Logical English one is an LE program for LPS (the IDE's
 *  kind of .le): small, runnable, and showing each part once. */
const NEW_LPS = 'maxTime(10).\n\n';
const NEW_LE = `the target language is: lps.

the maximum time is 5.

the actions are:
    *a person* enters the room.

the fluents are:
    *a person* is inside.
    the room is closed.

the knowledge base new program includes:

when a person enters the room from a time to a second time
then the person is inside.

% nobody enters the room while it is closed
it must not be true that
    a person enters the room from a time to a second time
    and the room is closed at the time.

scenario one is:
    alice enters the room from 1 to 2.
`;

function buildMenus() {
  const menu = (name, items) => {
    const d = el('div', { class: 'menu' }, el('span', { class: 'menu-title', text: name }));
    const drop = el('div', { class: 'dropdown' });
    //  Every item says what it does in its tooltip (`tip`); an item that
    //  needs something the IDE may not have (`when`: an LE program open,
    //  LE2 reachable) is greyed out, with its tooltip saying why, each time
    //  the menu opens.
    const refresh = [];
    for (const it of items) {
      if (it === '-') { drop.appendChild(el('div', { class: 'sep' })); continue; }
      let node;
      if (it.href) {
        node = el('a', { class: 'item', href: it.href, target: '_blank', rel: 'noopener', text: it.label });
      } else {
        node = el('div', { class: 'item', text: it.label, onclick: () => {
          if (node.classList.contains('disabled')) return;
          it.run(); d.classList.remove('open');
        } });
      }
      if (it.tip) node.title = it.tip;
      if (it.when) refresh.push(() => {
        const why = it.when();          // true, or the reason it does not apply
        node.classList.toggle('disabled', why !== true);
        node.title = why === true ? (it.tip || '') : `${it.tip || ''}\n\n(${why})`;
      });
      drop.appendChild(node);
    }
    d.appendChild(drop);
    d.addEventListener('click', (e) => {
      if (e.target.closest('.dropdown')) return;
      const open = d.classList.contains('open');
      for (const o of document.querySelectorAll('.menu.open')) o.classList.remove('open');
      if (!open) for (const f of refresh) f();
      d.classList.toggle('open', !open);
    });
    return d;
  };
  const activeName = () => tabs.activeTab()?.name || '';
  const isLeTab = () => /\.le$/i.test(activeName());
  const leLpsTab = () => {
    if (!isLeTab()) return 'the active file is not a Logical English (.le) program';
    return /the target language is\s*:?\s*lps\b/i.test(state.editor.getValue())
      || 'the program does not declare "the target language is: lps."';
  };
  const needsLe = () => state.leAvailable !== false
    || 'Logical English needs LE2 on this server (LPS_LE2_LIB, LPS_LE2_URL or LPS_LE2_DIR)';
  document.addEventListener('click', (e) => {
    if (!e.target.closest('.menu')) for (const o of document.querySelectorAll('.menu.open')) o.classList.remove('open');
  });

  const ed = () => state.editor;
  $('menubar').replaceChildren(
    menu('File', [
      { label: 'New LPS program (.lps)', run: () => tabs.openTab(NEW_LPS, 'untitled.lps'),
        tip: 'A new tab with an empty LPS program in the internal (Prolog-like) syntax' },
      { label: 'New Logical English program (.le)', run: () => tabs.openTab(NEW_LE, 'untitled.le'),
        tip: 'A new tab with a small Logical English program for LPS (the target language is: lps): events, fluents, a law and a scenario to start from',
        when: needsLe },
      { label: 'Open…', run: fileOpen,
        tip: 'Open files from this computer: LPS programs (.lps, .pl, .P), Logical English programs (.le), or a file of another system that is converted on opening — a PDDL planning domain (.pddl), a Drools rule file (.drl), a Solidity contract (.sol)' },
      { label: 'Open example from server…', run: openExamples,
        tip: 'Pick one of the example programs this server keeps, grouped by folder' },
      '-',
      { label: 'Save', run: () => fileSave(false),
        tip: 'Save the active file: back to the file it was opened from when the browser allows it, otherwise asking where' },
      { label: 'Save As…', run: () => fileSave(true),
        tip: 'Save the active file under a new name' },
      '-',
      { label: 'Close file', run: () => tabs.closeTab(tabs.activeTab()?.id),
        tip: 'Close the active tab (asking first if it has unsaved changes)' },
      '-',
      { label: 'Copy share link', run: copyShareLink,
        tip: 'Copy a link that carries this program\'s text as it is now: following it opens the program in this IDE' },
    ]),
    menu('Edit', [
      { label: 'Undo', run: () => ed().trigger('menu', 'undo'), tip: 'Undo the last change (Ctrl/Cmd+Z)' },
      { label: 'Redo', run: () => ed().trigger('menu', 'redo'), tip: 'Redo the change just undone (Ctrl/Cmd+Shift+Z)' },
      '-',
      { label: 'Find', run: () => ed().trigger('menu', 'actions.find'), tip: 'Find text in the active file (Ctrl/Cmd+F)' },
      { label: 'Replace', run: () => ed().trigger('menu', 'editor.action.startFindReplaceAction'),
        tip: 'Find text and replace it (Ctrl/Cmd+H)' },
      { label: 'Go to line…', run: () => ed().trigger('menu', 'editor.action.gotoLine'),
        tip: 'Move the cursor to a line by its number (Ctrl+G)' },
      '-',
      { label: 'Toggle line comment', run: () => ed().trigger('menu', 'editor.action.commentLine'),
        tip: 'Comment out the selected lines, or uncomment them (Ctrl/Cmd+/)' },
      { label: 'Toggle block comment', run: () => ed().trigger('menu', 'editor.action.blockComment'),
        tip: 'Wrap the selection in a block comment, or unwrap it' },
      '-',
      { label: 'Collapse all clauses', run: foldAllClauses,
        tip: 'Fold every clause to its first line, to see the program\'s outline' },
      { label: 'Expand all', run: () => ed().trigger('menu', 'editor.unfoldAll'), tip: 'Unfold everything folded' },
      '-',
      { label: 'Next problem (F8)', run: () => ed().trigger('menu', 'editor.action.marker.next'),
        tip: 'Go to the next error or warning the checker found in the file' },
      '-',
      { label: 'Insert a construct…', run: showSnippets,
        tip: 'Insert a ready-made piece of program (a reactive rule, a causal law, a constraint…) at the cursor' },
      { label: 'Say it in English…', run: englishToLe,
        tip: 'Write a sentence in plain English and have an LLM turn it into Logical English with the document\'s own templates, checked against the program: it is shown for you to copy, never inserted',
        when: () => (isLeTab() || 'the active file is not a Logical English (.le) document') === true ? needsLe() : 'the active file is not a Logical English (.le) document' },
    ]),
    menu('View', [
      { label: 'The original this was converted from', run: showOriginal,
        tip: 'Show the file this program was converted from (a Solidity contract, a Drools or PDDL file…): the one opened in this session, or the sources folder beside a program opened from the server' },
      { label: 'Legal view: who may do what (Logical English)', run: showLegalView,
        tip: 'The legal view of this Logical English LPS program, computed from it and from its run: who may do what, when, and with which effect — each action\'s integrity constraints as one permission rule, each causal law as an effect, a scenario with the state before each call of the program\'s scenario. It is an ordinary Logical English program: its queries are answered in the Logical English editor.',
        when: () => { const w = leLpsTab(); return w === true ? needsLe() : w; } },
      { label: 'Compare with the previous run', run: showRunDiff,
        tip: 'Show what each cycle changed (fluents initiated, terminated, updated) in this run and in the previous one, side by side' },
      '-',
      { label: 'Documentation beside the editor', run: toggleDocPane,
        tip: 'Open or close the documentation pane to the right of the editor' },
      '-',
      { label: 'Assistant panel', run: () => toggleDock('assistant'),
        tip: 'Open or close the assistant: ask an LLM about the program, or to change it' },
      { label: 'Live execution panel', run: () => toggleDock('live'),
        tip: 'Open or close the live panel: run the program cycle by cycle and inject events while it runs' },
      { label: 'Play panel (interactive fiction)', run: () => toggleDock('play'),
        tip: 'Open or close the play panel: play a program written as an interactive story by typing commands' },
    ]),
    menu('Misc', [
      { label: 'Theme: dark', run: () => setTheme('lps-dark'), tip: 'Light text on a dark background' },
      { label: 'Theme: light', run: () => setTheme('lps-light'), tip: 'Dark text on a light background' },
      { label: 'Theme: high contrast', run: () => setTheme('lps-hc'), tip: 'Maximum contrast, for low vision or bright rooms' },
      '-',
      { label: 'Font: small', run: () => setFontSize(11), tip: 'The editor\'s text at 11 pixels' },
      { label: 'Font: medium', run: () => setFontSize(13), tip: 'The editor\'s text at 13 pixels' },
      { label: 'Font: large', run: () => setFontSize(16), tip: 'The editor\'s text at 16 pixels' },
      '-',
      { label: 'API keys, models & Assistant settings…', run: () => window.dispatchEvent(new Event('lps-open-settings')),
        tip: 'The LLM providers\' API keys and the models the assistant and "Say it in English" use (kept in this browser)' },
      { label: 'Server token…', run: () => openTokenDialog(),
        tip: 'The token this server asks for (LPS_TOKEN), when it was started with one' },
      '-',
      { label: 'Deploy as WASM…', run: () => window.dispatchEvent(new Event('lps-deploy-wasm')),
        tip: 'Bundle the program with SWI-Prolog\'s WebAssembly runtime into a page that runs it in a browser, without this server' },
      { label: 'Deploy as Solidity…', run: () => window.dispatchEvent(new Event('lps-deploy-solidity')),
        tip: 'Check whether the program can be written as a Solidity smart contract (and say why not if it cannot); if it can, show the contract to copy and open it in the Remix online IDE' },
      { label: 'Export to another system…', run: () => window.dispatchEvent(new Event('lps-export')),
        tip: 'Write this Logical English document in another system\'s format with an exporter of the Logical English installation (a Miniscript policy, LegalRuleML, Daml…): shown to copy or save, with a link to a public sandbox where there is one',
        when: () => (isLeTab() || 'the active file is not a Logical English (.le) document') === true ? needsLe() : 'the active file is not a Logical English (.le) document' },
    ]),
    menu('Help', [
      { label: 'All the examples (the start page)', href: '/', tip: 'The start page, with every example program this server keeps' },
      { label: 'Keyboard shortcuts…', run: showShortcuts, tip: 'The keys the editor responds to' },
      '-',
      { label: 'Using the editor', href: '/docs/UsingTheIDE', tip: 'The manual of this IDE, in a new tab' },
      { label: 'Learning LPS — the tutorial', href: '/docs/lps_tutorial', tip: 'A step-by-step introduction to LPS, in a new tab' },
      { label: 'Language reference', href: '/docs/lps_summary', tip: 'Every LPS construct, in a new tab' },
      { label: 'Glossary', href: '/docs/glossary', tip: 'The terms the documentation uses (fluent, event, cycle…), in a new tab' },
      { label: 'Introducing LPS2', href: '/docs/IntroducingLPS2', tip: 'What LPS2 is and how it differs from the original LPS, in a new tab' },
      '-',
      { label: 'About the icons used in animations…', run: showIcons, tip: 'The icons the scenes can draw, searchable by name or meaning, with their sets' },
      { label: 'About LPS2…', run: showAbout, tip: 'What LPS2 is, where the language comes from, the licences of the libraries it uses, and the build' },
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

/*  The rule forms, as a palette. The syntax is the first barrier — a reader who
 *  knows what they want to say still has to remember whether it is `initiates`
 *  or `initiate` — and completion only helps if you already know the word. */
const CONSTRUCTS = [
  ['a reactive rule', 'if   Condition at T\nthen action from T to T2.'],
  ['a causal law (initiates)', 'event initiates fluent.'],
  ['a causal law (terminates)', 'event terminates fluent.'],
  ['a causal law (updates)', 'event updates Old to New in fluent(Old).'],
  ['a constraint', 'false condition1 at T, condition2 at T.'],
  ['declarations', 'fluents f(_).\nevents  e(_).\nactions a(_).'],
  ['the initial state', 'initially f(a), f(b).'],
  ['an observation', 'observe e(x) from 1 to 2.'],
  ['a goal to plan for', 'achieve f(a), f(b).'],
  ['an intensional fluent', 'derived(X) at T if base(X) at T.'],
  ['a composite event', 'together(X) from T1 to T2 if first(X) from T1 to T, second(X) from T to T2.'],
  ['a 2D drawing rule', 'display(fluent(X),\n\t[type:circle, point:[X, 0], radius:20, fillColor:green]).'],
  ['a 3D drawing rule', 'display3d(fluent(X),\n\t[type:box, position:[X, 0, 0], size:[1,1,1], color:green]).'],
  ['the planning directive', ':- lps_engine(planning, [search(auto), horizon(12), max_concurrency(1)]).'],
];

function showSnippets() {
  const list = el('div', { class: 'list' }, ...CONSTRUCTS.map(([label, text]) => {
    const row = el('div', { class: 'row' },
      el('span', { class: 'ex-name', text: label }),
      el('code', { class: 'ex-title', text: text.split('\n')[0] }));
    row.addEventListener('click', () => {
      const ed2 = state.editor, pos = ed2.getPosition();
      ed2.executeEdits('snippet', [{
        range: { startLineNumber: pos.lineNumber, startColumn: pos.column, endLineNumber: pos.lineNumber, endColumn: pos.column },
        text: text + '\n',
      }]);
      closeDialog(); ed2.focus();
    });
    return row;
  }));
  openDialog('Insert a construct', list);
}

/*  The file this buffer was converted from. A `.pddl` opens as LPS, and the
 *  first question anyone has about a translation is what the original said. */
function showOriginal() {
  const t = tabs.activeTab();
  if (!t?.original) {
    setStatus(t?.origin ? 'the original was not kept for this file' : 'this file was not converted from anything');
    return;
  }
  openDialog(`${t.origin} — the source this was converted from`,
    el('pre', { class: 'internal', text: t.original }));
}

/*  The legal view of a Logical English LPS document (LE2's le_lps_legal.pl):
 *  each action's integrity constraints as one permission rule, each causal
 *  law as an effect — a timeless LE program, opened in a tab of its own. Its
 *  queries are answered by LE2's editor, not by this engine, so the status
 *  line says where to run them. */
async function showLegalView() {
  const t = tabs.activeTab();
  if (!t || !/\.le$/i.test(t.name || '')) {
    setStatus('the legal view is drawn from a Logical English LPS document (.le)');
    return;
  }
  setStatus('drawing the legal view…');
  try {
    const r = await api.api({ operation: 'le_legal_view', source: state.editor.getValue() });
    if (!r.ok) { setStatus(r.error || r.message || 'no legal view'); return; }
    const stem = (t.name || 'program.le').replace(/\.le$/i, '');
    loadSource(r.source, `${stem}_legal_view.le`);
    setStatus('the legal view is an ordinary Logical English program: run its queries in the Logical English editor');
  } catch (e) {
    setStatus(`no legal view: ${e.message}`);
  }
}

/*  Two runs of the same file, side by side. Change one rule and the question is
 *  what that changed; without this the only way to answer it is to remember. */
async function showRunDiff() {
  const t = tabs.activeTab();
  if (!t?.prevRun || !t?.thisRun) { setStatus('run this file twice to compare'); return; }
  const body = el('div', { class: 'rundiff' }, el('p', { class: 'empty', text: 'reading both traces…' }));
  openDialog('This run against the previous one', body);
  const read = async (r) => {
    const out = [];
    for (let c = 1; c <= r.cycle; c++) {
      try {
        const ch = await api.changes(r.session, c);
        const bits = [...(ch.initiated || []).map((x) => '+' + x.fluent),
          ...(ch.terminated || []).map((x) => '-' + x.fluent),
          ...(ch.updated || []).map((x) => '~' + x.fluent)];
        out.push(`${c}: ${bits.join(' ') || '—'}`);
      } catch { out.push(`${c}: (gone)`); }
    }
    return out;
  };
  const [a, b] = await Promise.all([read(t.prevRun), read(t.thisRun)]);
  const rows = [];
  for (let i = 0; i < Math.max(a.length, b.length); i++) {
    const same = a[i] === b[i];
    rows.push(el('div', { class: 'diffrow' + (same ? '' : ' differs') },
      el('code', { text: a[i] || '' }), el('code', { text: b[i] || '' })));
  }
  body.replaceChildren(
    el('div', { class: 'diffrow head' },
      el('b', { text: `previous — ${t.prevRun.status} after ${t.prevRun.cycle}` }),
      el('b', { text: `this run — ${t.thisRun.status} after ${t.thisRun.cycle}` })),
    ...rows);
}

/*  The documents open in a new tab, which loses the workspace. This docks one
 *  beside the editor instead — the same page, in an iframe, so there is one
 *  renderer and no second copy of the markdown. */
function toggleDocPane() {
  let f = document.getElementById('docpane');
  if (f) { f.remove(); window.dispatchEvent(new Event('lps-dock')); return; }
  f = el('iframe', { id: 'docpane', src: '/docs/UsingTheIDE', title: 'documentation' });
  document.getElementById('right').appendChild(f);
  window.dispatchEvent(new Event('lps-dock'));
}

const SHORTCUTS = [
  ['Ctrl/Cmd + Enter', 'run the program'],
  ['Ctrl/Cmd + .', 'run one more cycle'],
  ['← →', 'previous / next cycle'],
  ['Home / End', 'first / last cycle'],
  ['space', 'play or pause the cycles'],
  ['F8', 'next problem'],
  ['Ctrl/Cmd + F', 'find'],
  ['Ctrl/Cmd + H', 'replace'],
  ['Ctrl/Cmd + F12', 'show definition'],
  ['right-click in a pane', 'why did this happen?'],
  ['right-click in the editor', 'the LPS actions: run, internal syntax, why, observe'],
  ['double-click a scene', 'fit it to the pane'],
  ['Esc', 'close a dialog'],
];

function showShortcuts() {
  openDialog('Keyboard shortcuts',
    el('table', { class: 'changes' }, el('tbody', {},
      ...SHORTCUTS.map(([k, what]) => el('tr', {},
        el('td', {}, el('code', { text: k })), el('td', { text: what }))))));
}

/*  English in, Logical English out — LE2's `nl_to_le`, which asks a model for a
 *  fragment and then verifies it against this program before offering it.
 *
 *  Shown, never inserted: a mistranslated sentence is a sentence the author did
 *  not write, and the point of Logical English is that what is written is what
 *  is meant. */
async function englishToLe() {
  /*  Both refusals used to be a line in the status bar, which from a menu item
   *  reads as the item doing nothing: the bar is one line at the foot of the
   *  window, nowhere near the click, and the file it refuses is nearly always
   *  an ordinary `.lps` one, since Logical English documents live in LE2. Say
   *  it where every other menu item's answer appears. */
  if (tabs.syntaxOf(state.fileName) !== 'le') {
    openDialog('Say it in English',
      el('div', { class: 'why' },
        el('p', { text: `This translates a sentence into Logical English, using only the `
          + `templates a Logical English document declares — and ${state.fileName} is an LPS `
          + `program, which declares none.` }),
        el('p', { class: 'muted', text: 'Open a ".le" document, or save this one under that '
          + 'extension, and the item works on it.' })));
    return;
  }
  const le = await checkLeAvailable();
  if (!le.available) {
    openDialog('Say it in English',
      el('div', { class: 'why' },
        el('p', { text: le.message || 'Logical English needs LE2 loaded into this server.' }),
        el('p', { class: 'muted', text: 'Start it with LPS_LE2_LIB pointing at an LE2 checkout.' })));
    return;
  }
  const input = el('input', { class: 'filter', placeholder: 'e.g. the wolf is at the north bank' });
  const kind = el('select', {},
    el('option', { value: 'facts', text: 'facts, for a scenario' }),
    el('option', { value: 'query', text: 'a query' }));
  const out = el('div', { class: 'why-answer' });
  const go = async () => {
    const t = input.value.trim();
    if (!t) return;
    out.replaceChildren(el('p', { class: 'empty', text: 'asking, and checking the answer against this program…' }));
    try {
      const r = await api.api({
        operation: 'le_nl', sentence: t, source: state.editor.getValue(),
        kind: kind.value,
        model: document.getElementById('assistant-model')?.value || null,
        api_keys: JSON.parse(localStorage.getItem('lps.keys') || '{}'),
      });
      if (!r.ok) { out.replaceChildren(el('p', { class: 'empty', text: r.error || 'no answer' })); return; }
      const insert = el('button', { class: 'primary', text: 'Insert at the cursor' });
      insert.addEventListener('click', () => {
        const ed = state.editor, pos = ed.getPosition();
        ed.executeEdits('le-nl', [{
          range: { startLineNumber: pos.lineNumber, startColumn: pos.column,
            endLineNumber: pos.lineNumber, endColumn: pos.column },
          text: r.le,
        }]);
        closeDialog(); ed.focus();
      });
      out.replaceChildren(
        el('pre', { class: 'internal', text: r.le }),
        (r.issues || []).length
          ? el('p', { class: 'muted', text: `${r.issues.length} issue(s) the check could not clear — read it before inserting` })
          : el('p', { class: 'muted', text: 'verified against this program: no new issues' }),
        insert);
    } catch (e) { out.replaceChildren(el('p', { class: 'empty', text: e.message })); }
  };
  input.addEventListener('keydown', (e) => { if (e.key === 'Enter') go(); });
  openDialog('Say it in English',
    el('div', { class: 'why' },
      el('div', { class: 'why-notrow' }, kind, input,
        el('button', { text: 'Translate', onclick: go })),
      out,
      el('p', { class: 'muted why-forms', text: 'LE2 turns the sentence into Logical English using only the templates this document declares, then checks the result against the program and refines it. Nothing is inserted until you say so.' })));
  input.focus();
}

/*  The token dialog, which is also the recovery path.
 *
 *  A deployment started with `LPS_TOKEN` refuses every operation, so without
 *  this the IDE is a text editor that cannot compile, list an example or run
 *  anything — and says nothing about why. `onSaved` is what the caller wanted
 *  to do; it runs again once there is a token to do it with. */
function openTokenDialog(why, onSaved) {
  const inp = el('input', { type: 'password', value: api.getToken(), placeholder: 'LPS_TOKEN' });
  const save = () => {
    api.setToken(inp.value.trim());
    closeDialog();
    if (onSaved) onSaved();
  };
  inp.addEventListener('keydown', (e) => { if (e.key === 'Enter') save(); });
  openDialog('Server token',
    el('div', {},
      el('p', { text: why || 'Required when the server was started with LPS_TOKEN set.' }),
      inp,
      el('p', { class: 'muted', text: 'It is kept in this browser. A link can carry it as ?token=… — '
        + 'the IDE stores that and takes it back out of the address bar.' })),
    [
      el('button', { text: 'Cancel', onclick: closeDialog }),
      el('button', { class: 'primary', text: 'Save', onclick: save }),
    ]);
  setTimeout(() => inp.focus(), 50);
}

/*  Every path that talks to the server funnels its failures through here, so
 *  "unauthorised" is answered with the dialog that fixes it rather than with a
 *  status line nobody reads or, worse, silence. */
function reportApiError(e, what, retry) {
  if (e && e.unauthorised) {
    setStatus('this server needs a token');
    openTokenDialog(`This server was started with LPS_TOKEN set, so ${what} was refused. `
      + 'Paste the token to continue.', retry);
    return true;
  }
  setStatus(`${what} failed: ${e.message}`);
  return false;
}

/*  The index is *bundled*, not fetched: ui/fetch-icons.mjs generates
 *  src/generated/icon-index.js at build time and the icon files are served
 *  beside it. An earlier version of this dialog fetched
 *  `/assets/icons/manifest.json`, which is not a route — the 404 body parsed
 *  as JSON, `m.icons` was undefined, and it reported a library of nought. */
function showIcons() {
  const filter = el('input', { class: 'filter', placeholder: 'filter by name or meaning…' });
  const list = el('div', { class: 'iconlist' });
  const draw = () => {
    const f = filter.value.trim().toLowerCase();
    const shown = ICONS.filter((i) => !f || i.name.includes(f)
      || (i.desc || '').toLowerCase().includes(f)
      || (i.concepts || []).some((c) => c.includes(f)));
    list.replaceChildren(...shown.map((i) => el('span', {
      class: 'icontag', title: `${i.desc || i.name}  ·  ${i.set}`,
    },
    el('img', { src: iconUrl(i.name), alt: i.name, loading: 'lazy' }),
    el('code', { text: i.name }))));
    count.textContent = `${shown.length} of ${ICONS.length}`;
  };
  const count = el('span', { class: 'muted' });
  filter.addEventListener('input', draw);

  openDialog('The icons used in animations',
    el('div', { class: 'about' },
      el('p', {}, el('span', { text: 'A ' }), el('b', { text: `${ICONS.length}-icon library` }),
        el('span', { text: ' is checked into this repository and served from this server, so a deployment with no internet still animates. Reach one from a program with ' }),
        el('code', { text: '[type:raster, icon:NAME]' }), el('span', { text: '.' })),
      el('p', { class: 'muted', text: 'The set was chosen by a functor census over the corpus — finance and contracts, legal and governance, puzzles and games, places and motion — so the names are the words a fluent or an action is likely to be called.' }),
      el('h4', { text: 'Where they come from' }),
      el('ul', {}, ...Object.entries(ICON_LICENSES).map(([k, v]) =>
        el('li', {}, el('b', { text: k }), el('span', { text: ` — ${v.license}, ${v.attribution}` })))),
      el('h4', {}, el('span', { text: 'The names ' }), count),
      filter, list));
  draw();
}

function showAbout() {
  const link = (href, text) => el('a', { href, target: '_blank', rel: 'noopener', text });
  openDialog('LPS2', el('div', { class: 'about' },
    el('p', { text: 'A reimplementation of the LPS engine in SWI-Prolog, held to LPS1’s own corpus trace-for-trace.' }),
    //  Where the language came from, and who is behind it. A reimplementation
    //  should say what it is a reimplementation *of*.
    el('p', {},
      el('span', { text: 'The language is Kowalski and Sadri’s: ' }),
      link('http://lps.doc.ic.ac.uk', 'lps.doc.ic.ac.uk'),
      el('span', { text: ' at Imperial College. LPS is developed commercially by ' }),
      link('https://logicalcontracts.com', 'Logical Contracts'),
      el('span', { text: '.' })),
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

/*  Open or close one of the two docks. There are three ways in — View ▸ …panel,
 *  the Live button in the bar, and a panel's own × — and they are all this:
 *  flip `collapsed`, then let `makeDockSplitters` re-lay the column out. */
export function toggleDock(which) {
  $(which).classList.toggle('collapsed');
  window.dispatchEvent(new Event('lps-dock'));
}

/*  The left column is a grid of [tabs, editor, grip, assistant, grip, live].
 *  Both docks are resizable, and remember their height — an assistant you have
 *  to scroll to read is an assistant you stop reading.
 *
 *  A closed dock now leaves nothing behind: no toolbar, no title, and no grip
 *  either. Its row and its grip's row both go to zero, so the editor has the
 *  whole column, and the only trace of the panel is its item in View, or the
 *  lit or unlit Live button. */
function makeDockSplitters() {
  const left = $('left');
  const sizes = { assistant: store.get('h.assistant', 220), live: store.get('h.live', 220),
                  play: store.get('h.play', 260) };
  const apply = () => {
    const open = { assistant: !$('assistant').classList.contains('collapsed'),
                   live: !$('live').classList.contains('collapsed'),
                   play: !$('play').classList.contains('collapsed') };
    const a = open.assistant ? sizes.assistant : 0;
    const l = open.live ? sizes.live : 0;
    const p = open.play ? sizes.play : 0;
    left.style.gridTemplateRows =
      `auto 1fr ${a ? '4px' : '0px'} ${a}px ${l ? '4px' : '0px'} ${l}px ${p ? '4px' : '0px'} ${p}px`;
    //  A panel that has a button in the top bar — Live and Play do, the
    //  assistant is reached from View — shows there whether it is open.
    for (const which of ['assistant', 'live', 'play']) {
      const b = $(which + '-toggle');
      if (b) b.setAttribute('aria-pressed', open[which] ? 'true' : 'false');
    }
  };
  apply();
  window.addEventListener('lps-dock', apply);
  for (const which of ['assistant', 'live', 'play']) {
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

export function setStatus(msg, cls) {
  const s = $('status');
  s.textContent = msg;
  s.classList.remove('has-errors', 'has-warnings');
  if (cls) s.classList.add(cls);
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

  initWhy({ state, api, openDialog, closeDialog, setStatus, renderExplanation, goToLine });

  $('run').addEventListener('click', () => runProgram());
  $('max-time').addEventListener('input', (e) => {
    //  Once it has been typed in, the analysis stops overwriting it — and
    //  clearing it hands it back.
    if (e.target.value.trim()) e.target.dataset.edited = '1';
    else delete e.target.dataset.edited;
  });
  $('status').addEventListener('click', () => state.editor.trigger('status', 'editor.action.marker.next'));
  $('cycle-slider').addEventListener('input', (e) => setCycle(Number(e.target.value)));
  $('cycle-prev').addEventListener('click', () => stepCycle(-1));
  $('cycle-next').addEventListener('click', () => stepCycle(1));
  $('cycle-first').addEventListener('click', () => setCycle(0));
  $('cycle-last').addEventListener('click', () => setCycle(state.maxCycle));
  $('cycle-play').addEventListener('click', playCycles);

  /*  The arrow keys used to work only while the slider had focus, which meant
   *  clicking a 4-pixel-tall control before you could step. They now work
   *  anywhere outside a text field. */
  document.addEventListener('keydown', (e) => {
    if (e.target.closest('input, textarea, .monaco-editor')) return;
    if (e.metaKey || e.ctrlKey || e.altKey) return;
    if (e.key === 'ArrowLeft') { stepCycle(-1); e.preventDefault(); }
    else if (e.key === 'ArrowRight') { stepCycle(1); e.preventDefault(); }
    else if (e.key === 'Home') { setCycle(0); e.preventDefault(); }
    else if (e.key === 'End') { setCycle(state.maxCycle); e.preventDefault(); }
    else if (e.key === ' ') { playCycles(); e.preventDefault(); }
  });
  $('file-input').addEventListener('change', async (e) => {
    for (const f of e.target.files) await loadPossiblyForeign(await f.text(), f.name);
  });
  for (const id of ['dfa-abstract', 'dfa-nonreflexive']) {
    $(id)?.addEventListener('change', () => refreshPane());
  }
  $('dialog-close').addEventListener('click', closeDialog);
  document.addEventListener('keydown', (e) => { if (e.key === 'Escape') closeDialog(); });

  /*  A panel is closed from its own × as well as from where it was opened.
   *  View (and, for Live, the button in the bar) is where you go to open one;
   *  the × is where your hand already is when you want it gone. */
  for (const b of document.querySelectorAll('.dock-close')) {
    b.addEventListener('click', () => {
      $(b.dataset.dock).classList.add('collapsed');
      window.dispatchEvent(new Event('lps-dock'));
    });
  }

  /* "Deploy as WASM" (M11): the server bundles the engine's core sources and
   * this program into one page that runs in a browser with no server at all.
   * It opens in a new tab and can be saved. */
  /* "Deploy as Solidity": the program in the editor as a Solidity contract
   * (src/syntax/lps_solidity.pl) — or, when something in it has no straight
   * translation, the list of those things, each a link to its line. The
   * contract can be copied, or opened in a public sandbox (Remix IDE, whose
   * address carries the source) to compile, deploy on its in-browser chain
   * and call. The server names the sandbox, so its address lives in one place. */
  window.addEventListener('lps-deploy-solidity', async () => {
    setStatus('translating to Solidity…');
    let r;
    try {
      r = await api.api({ operation: 'to_solidity', source: state.editor.getValue(), name: state.fileName });
    } catch (e) {
      setStatus(`Deploy as Solidity: ${e.message}`, 'has-errors');
      return;
    }
    const lineOf = (d) => d.source?.line || 0;
    const jump = (line) => { closeDialog(); if (line) goToLine(line); };
    if (!r.compatible) {
      const problems = r.problems || [];
      const list = el('ul', { class: 'sol-problems' },
        ...problems.map((d) => {
          const line = lineOf(d);
          const text = line ? (state.editor.getModel().getLineContent(line) || '').trim() : '';
          return el('li', {},
            line ? el('a', { href: '#', class: 'sol-line', text: `line ${line}`, onclick: (e) => { e.preventDefault(); jump(line); } })
                 : el('span', { class: 'muted', text: 'the program' }),
            el('span', { text: ' — ' }), el('b', { text: d.code }), el('span', { text: `: ${d.message}` }),
            text ? el('pre', { class: 'code sol-src', text }) : el('span'));
        }));
      openDialog('Deploy as Solidity — not translatable',
        el('div', { class: 'sol-dialog' },
          el('p', {}, el('span', { text: r.compiled === false
            ? 'The program does not compile, so there is nothing to translate yet:'
            : `${problems.length} thing(s) in this program have no straight translation to Solidity. A contract only answers calls, holds one value per key, and has integers only; nothing was written, rather than a contract that means something else:` })),
          list));
      setStatus(`not translatable to Solidity: ${problems.length} problem(s)`, 'has-errors');
      return;
    }
    const copy = el('button', { text: 'Copy source', onclick: async () => {
      try { await navigator.clipboard.writeText(r.solidity); setStatus('Solidity copied'); copy.textContent = 'Copied'; }
      catch { setStatus('the browser refused the clipboard: select the text and copy it', 'has-errors'); }
    } });
    const open = el('button', { class: 'primary', text: `Open in ${r.sandbox.name} ↗`, onclick: () => {
      window.open(r.sandbox.url, '_blank', 'noopener');
    } });
    const lines = r.solidity.split('\n').length;
    const notes = (r.notes || []).map((d) => el('li', { text: d.message }));
    openDialog(`Deploy as Solidity — contract ${r.contract}`,
      el('div', { class: 'sol-dialog' },
        el('p', {},
          el('span', { text: `${state.fileName} as a Solidity contract of ${lines} lines: fluents are state (with a has… flag where a value can be absent), actions are functions called by msg.sender, integrity constraints revert, causal laws write. ` }),
          el('b', { text: `Open in ${r.sandbox.name}` }),
          el('span', { text: ' loads it into a fresh workspace and compiles it; deploy it on the in-browser chain (Deploy & run ▸ Remix VM) and call its functions — the comment at the top lists the program’s own scenario as calls to make.' })),
        el('p', { class: 'muted', text: 'It is a contract of this program, not of a standard: functions are named after the actions and take the addresses first, then the values (Solidity’s convention, so transfer(to, value) has the ERC-20 selector); the public getters are named after the fluents (balance, not balanceOf). Where the program and a standard share their names, the interfaces agree; check before handing it to a wallet.' }),
        notes.length ? el('ul', { class: 'muted' }, ...notes) : el('span'),
        el('pre', { class: 'code sol-code', text: r.solidity })),
      [copy, open, el('button', { text: 'Close', onclick: closeDialog })]);
    setStatus(`Solidity: contract ${r.contract}, ${lines} lines`);
  });

  /* "Export to another system": the Logical English document written by an
   * exporter of the LE installation (le_import.pl's registry, reached through
   * le_service) — only those that can write it are offered. The result is
   * shown to copy or save, with the exporter's notes and its links (a public
   * sandbox the result opens in). */
  window.addEventListener('lps-export', async () => {
    const source = state.editor.getValue();
    let formats = [];
    try { formats = (await api.api({ operation: 'export_formats', source, name: state.fileName })).formats || []; }
    catch (e) { setStatus(`Export: ${e.message}`, 'has-errors'); return; }
    if (!formats.length) {
      openDialog('Export to another system', el('p', { text: 'No exporter of the Logical English installation can write this document in another system\'s format.' }));
      return;
    }
    const run = async (f) => {
      closeDialog();
      setStatus(`writing ${f.title}…`);
      let r;
      try { r = await api.api({ operation: 'export', source, name: state.fileName, exporter: f.id }); }
      catch (e) { setStatus(`Export: ${e.message}`, 'has-errors'); return; }
      if (!r.ok) { setStatus(`Export: ${r.error}`, 'has-errors'); return; }
      const copy = el('button', { text: 'Copy', onclick: async () => {
        try { await navigator.clipboard.writeText(r.document); copy.textContent = 'Copied'; }
        catch { setStatus('the browser refused the clipboard: select the text and copy it', 'has-errors'); }
      } });
      const save = el('button', { text: 'Save…', onclick: () => {
        const a = document.createElement('a');
        a.href = URL.createObjectURL(new Blob([r.document], { type: 'text/plain' }));
        a.download = r.fileName || 'exported.txt'; a.click();
        setTimeout(() => URL.revokeObjectURL(a.href), 1000);
      } });
      const links = (r.links || []).map((l) => el('button', { class: 'primary', text: `${l.title} ↗`, onclick: () => window.open(l.url, '_blank', 'noopener') }));
      openDialog(`Exported as ${r.exporter}`,
        el('div', { class: 'sol-dialog' },
          (r.notes || []).length ? el('ul', { class: 'muted' }, ...r.notes.map((n) => el('li', { text: n }))) : el('span'),
          el('pre', { class: 'code sol-code', text: r.document })),
        [copy, save, ...links, el('button', { text: 'Close', onclick: closeDialog })]);
      setStatus(`exported as ${r.fileName}`);
    };
    if (formats.length === 1) { run(formats[0]); return; }
    openDialog('Export to another system',
      el('ul', {}, ...formats.map((f) => el('li', {}, el('a', { href: '#', text: `${f.title} (.${f.extension})`,
                                                                onclick: (e) => { e.preventDefault(); run(f); } })))));
  });

  window.addEventListener('lps-deploy-wasm', async () => {
    setStatus('bundling…');
    try {
      /*  Two ways to point the page at the SWI-Prolog WebAssembly runtime, and
       *  the checkbox is the difference between them:
       *
       *  - **absolute** (default): the page fetches the runtime from *this*
       *    server. It works the moment you press Open, and it keeps working
       *    from anywhere that can reach this URL. A relative path would not:
       *    the page opens from a `blob:` URL, and a relative script src there
       *    resolves against the blob's own opaque origin, which is what made
       *    Open fail with `Can't find variable: SWIPL`.
       *  - **relative**: the page expects `swipl/` beside it. That is the form
       *    to save, serve, or wrap in a desktop application. */
      const standalone = { checked: false };
      const box = el('input', { type: 'checkbox' });
      box.addEventListener('change', () => { standalone.checked = box.checked; });

      const origin = new URL('/assets/swipl/swipl-web.js', location.origin).toString();
      const build = async () => api.api({
        operation: 'wasm_bundle', source: state.editor.getValue(),
        title: state.fileName,
        runtime: standalone.checked ? 'swipl/swipl-web.js' : origin,
      });

      let r = await build();
      let url = URL.createObjectURL(new Blob([r.html], { type: 'text/html' }));
      const stem = state.fileName.replace(/\.\w+$/, '');
      const dl = el('a', { class: 'item', href: url, download: stem + '-wasm.html', text: 'Download' });
      const open = el('button', { class: 'primary', text: 'Open', onclick: () => { window.open(url, '_blank'); closeDialog(); } });
      const size = el('b', { text: `${Math.round(r.html.length / 1024)} kB` });

      const desktop = el('div', { class: 'wasm-desktop' },
        el('h4', { text: 'As a desktop application' }),
        el('p', {}, el('span', { text: 'Tick ' }), el('b', { text: 'self-contained' }),
          el('span', { text: ' above, then wrap the page and a copy of this server’s ' }),
          el('code', { text: '/assets/swipl/' }),
          el('span', { text: ' directory with Tauri — a Rust shell around the system webview, so the result is a signed native binary of a few megabytes rather than a browser.' })),
        el('pre', { class: 'code', text:
          `npm create tauri-app@latest lps-app   # choose "vanilla", TypeScript: no
`
          + `cd lps-app
`
          + `#  put the saved page and the swipl/ directory in src/
`
          + `cp ~/Downloads/${stem}-wasm.html src/index.html
`
          + `cp -r /path/to/lps2/src/ide/dist/swipl src/swipl

`
          + `npm run tauri dev                    # try it
`
          + `npm run tauri build                  # a native binary

`
          + `#  what comes out:
`
          + `#    macOS    src-tauri/target/release/bundle/dmg/*.dmg
`
          + `#    Windows  src-tauri/target/release/bundle/msi/*.msi
`
          + `#    Linux    src-tauri/target/release/bundle/appimage/*.AppImage` }),
        el('p', { class: 'muted' },
          el('span', { text: 'Tauri needs Rust and each platform’s build tools; its prerequisites page lists them: ' }),
          el('a', { href: 'https://v2.tauri.app/start/prerequisites/', target: '_blank', rel: 'noopener', text: 'v2.tauri.app/start/prerequisites' }),
          el('span', { text: '. One caveat worth knowing before you start: a ' }),
          el('code', { text: '.wasm' }),
          el('span', { text: ' file must be served with its own MIME type, which Tauri’s asset protocol does — but a plain ' }),
          el('code', { text: 'file://' }), el('span', { text: ' page will not load it.' })));

      const note = el('p', { class: 'muted' });
      const retell = () => {
        note.textContent = standalone.checked
          ? 'Self-contained: the page will look for swipl/ beside itself. Save it, put a copy of this server’s /assets/swipl/ directory next to it, and serve the folder — Open will not work from here.'
          : `The page fetches the runtime from ${origin}. Open works now, and a saved copy keeps working wherever that URL is reachable.`;
        open.disabled = standalone.checked;
      };
      retell();

      box.addEventListener('change', async () => {
        setStatus('bundling…');
        r = await build();
        URL.revokeObjectURL(url);
        url = URL.createObjectURL(new Blob([r.html], { type: 'text/html' }));
        dl.href = url;
        size.textContent = `${Math.round(r.html.length / 1024)} kB`;
        retell();
        setStatus('bundled');
      });

      openDialog('Deploy as WASM',
        el('div', {},
          el('p', {}, el('span', { text: `${state.fileName} and the LPS2 engine, in one page of ` }), size,
            el('span', { text: '. It runs in the browser with no server of its own: the core is pure Prolog with no threads, sockets, clock or file I/O, which is the property tools/lint_core.pl has been enforcing since M1.' })),
          el('label', { class: 'wasm-opt' }, box,
            el('span', { text: ' self-contained — expect ' }), el('code', { text: 'swipl/' }),
            el('span', { text: ' beside the page rather than fetching it from this server' })),
          note,
          el('p', { class: 'muted', text: 'A .wasm file will not load over file://, so serve the folder:' }),
          el('pre', { class: 'code', text: 'python3 -m http.server 8000        # macOS, Linux\npy -m http.server 8000             # Windows\nnpx serve .                        # anywhere with Node' }),
          desktop),
        [
          el('button', { text: 'Close', onclick: closeDialog }),
          dl,
          open,
        ]);
      setStatus('bundled');
    } catch (e) { setStatus('bundle failed: ' + e.message); }
  });

  /*  Recording plays the run from the beginning while the scene pane's
   *  MediaRecorder is taking the canvas, then tells it to stop. The pane owns
   *  the recorder because it owns the canvas; the cycles are ours. */
  window.addEventListener('lps-record-play', async () => {
    const wait = (ms) => new Promise((r) => setTimeout(r, ms));
    setCycle(0);
    await wait(400);
    for (let c = 1; c <= state.maxCycle; c++) { setCycle(c); await wait(450); }
    await wait(600);
    window.dispatchEvent(new Event('lps-record-stop'));
    setStatus('recorded ' + state.maxCycle + ' cycles');
  });

  /*  This cycle beside the one before it. The before/after is the thing being
   *  taught, and scrubbing back and forth to see it is how you fail to. */
  window.addEventListener('lps-compare-cycles', async (e) => {
    const { kind, cycle } = e.detail;
    if (cycle < 1) { setStatus('nothing before cycle 0'); return; }
    const grab = async (c) => {
      setCycle(c);
      await refreshPane();
      await new Promise((r) => setTimeout(r, 350));
      const cv = $('pane-' + (kind === '3d' ? 'scene3d' : 'scene')).querySelector('canvas');
      return cv ? cv.toDataURL('image/png') : null;
    };
    const here = state.cycle;
    const before = await grab(cycle - 1);
    const after = await grab(cycle);
    await grab(here);
    openDialog(`cycle ${cycle - 1} and cycle ${cycle}`,
      el('div', { class: 'compare' },
        el('figure', {}, el('img', { src: before || '' }), el('figcaption', { text: `cycle ${cycle - 1}` })),
        el('figure', {}, el('img', { src: after || '' }), el('figcaption', { text: `cycle ${cycle}` }))));
  });

  /*  A left-click on an object goes to the next cycle in which its fluent
   *  changes — "when does this move next?", which is otherwise a scrub. */
  window.addEventListener('lps-pick', async (e) => {
    if (state.live) return;                       // a live scene is already moving
    if (state.playing) return;                    // the Play panel answers: the thing's last change
    const term = e.detail?.term;
    if (!term || !state.session) return;
    const head = String(term).replace(/\(.*$/, '');
    for (let c = state.cycle + 1; c <= state.maxCycle; c++) {
      try {
        const ch = await api.changes(state.session, c);
        const hit = ['initiated', 'terminated', 'updated']
          .some((k) => (ch[k] || []).some((x) => String(x.fluent).startsWith(head)));
        if (hit) { setCycle(c); setStatus(`${head} changes at cycle ${c}`); return; }
      } catch { break; }
    }
    setStatus(`${head} does not change again in this run`);
  });

  mountAssistant({ state, api, setStatus, openDialog, closeDialog, el });
  mountLive({ state, api, setStatus, el, refreshPane, setCycle, compileCurrent });
  const play = mountPlay({ state, api, setStatus, el, tabs, setCycle, setCycleBounds, refreshPane, markPaneAvailability });

  /*  An edit the editor did not see — the assistant writing a `.le` document's
   *  companion, which is another tab's model — still changes the program, and
   *  nothing else would re-read it: the analysis is driven by keystrokes in
   *  the buffer on screen. */
  window.addEventListener('lps-reanalyse', () => analyseNow());

  /*  An applied scene edit is followed by a run, because the point of the edit
   *  was the picture and the picture needs a trace. This is the one place the
   *  IDE runs a program the user did not ask it to, and it is confined to the
   *  case where they asked for the thing a run produces. */
  window.addEventListener('lps-assistant-applied', async (e) => {
    const what = e.detail?.what;
    try {
      await runProgram();
      selectPane(what === 'animate-3d' ? 'scene3d' : 'scene');
      await refreshPane();
      window.dispatchEvent(new CustomEvent('lps-assistant-ran', { detail: { what } }));
    } catch (err) {
      window.dispatchEvent(new CustomEvent('lps-assistant-ran',
        { detail: { what, error: 'the program did not run after that edit: ' + err.message } }));
    }
  });

  /*  A live tick repaints whichever scene pane is open, so the pane in the main
   *  window animates like the pop-out one does. Only the scenes: re-fetching a
   *  timeline twice a second would be a lot of work for a picture nobody is
   *  watching change. */
  window.addEventListener('lps-live-tick', (e) => {
    //  The badge and the status line follow every tick, whichever pane is open:
    //  a session ticking along behind a timeline of something else is the case
    //  this is here to stop.
    if (state.live) {
      setStatus(`live session · cycle ${e.detail.cycle}${e.detail.paused ? ' · paused' : ''}`);
    }
    if (state.pane !== 'scene' && state.pane !== 'scene3d') return;
    if (!state.live) return;
    $('cycle-label').textContent = `live · cycle ${e.detail.cycle}`;
    refreshPane();
  });

  /*  Starting or stopping a live session changes what the whole right-hand
   *  column is *about*, so the strip, the header and the badge are all re-read
   *  from it rather than each panel keeping its own idea. */
  window.addEventListener('lps-live-state', (e) => {
    markPaneAvailability();
    syncPaneHeader();
    if (!e.detail.running) {
      setStatus(state.lastRun ? state.lastRun + '  ·  live session ended' : 'live session ended');
    }
    //  On the way *in* as well as on the way out. Starting a session used to
    //  leave the pane showing whatever it showed before, so a program with no
    //  finished run sat there saying "nothing has been run yet" while the
    //  header beside it said LIVE and the cycle counter climbed.
    refreshPane();
  });

  /* A handle for the browser tests and the documentation's screenshot script.
   * Monaco is bundled, so `window.monaco` does not exist; without this a test
   * cannot put a program in the editor. */
  window.LPS = {
    state, api, monaco, tabs, load: loadSource, run: runProgram,
    pane: selectPane, refresh: refreshPane, setCycle, why: openWhy, toggleDock, play,
  };

  //  Which build this is. It is read once here and shown in "About LPS2…",
  //  which is enough: the top bar is for what acts on the program.
  fetch('/BUILD.txt').then((r) => (r.ok ? r.text() : null)).then((t) => {
    if (t) window.LPS_BUILD = t.trim();
  }).catch(() => {});

  //  The Logical English mode, if this server can compile it: the lexicon is
  //  a network call, and doing it at boot means the first `.le` opened is
  //  already coloured.
  checkLeAvailable().then((r) => { if (r.available) ensureLeMode(); });

  /*  Does this server want a token? Asked before anything is fetched: with
   *  `LPS_TOKEN` set every operation is refused, and the first thing that
   *  noticed used to be a `catch` that quietly opened an empty buffer. */
  const st = await api.serverStatus();
  if (st.token_required && !api.getToken()) {
    openTokenDialog('This server was started with LPS_TOKEN set. Nothing can be '
      + 'compiled, listed or run without it.', () => location.reload());
  }

  //  `/ide?example=NAME` — what every link on the landing page is.
  const wanted = new URLSearchParams(location.search).get('example');
  if (!loadFromHash()) {
    try {
      const e = await api.example(wanted || 'goat_declarative');
      loadSource(e.source, e.name ? e.name.split('/').pop() : 'goat_declarative.pl',
        e.converted_from ? { origin: e.converted_from, original: e.original } : undefined);
      openCompanion(e);
    } catch (e) {
      loadSource('maxTime(10).\n\n', 'untitled.lps');
      //  An empty buffer and no explanation is what this looked like from the
      //  outside: "the example did not open, and the editor works but nothing
      //  else does". Say which example, and why.
      reportApiError(e, `opening ${wanted || 'goat_declarative'}`,
        () => location.replace(location.href));
    }
  }
  restoreBuffers();
}

/*  One more cycle of the run already in progress, rather than a fresh run:
 *  `run` with a cycle count advances the *same* session, so stepping keeps the
 *  trace it has built. */
async function runMore(n) {
  if (!state.session) return runProgram(n);
  try {
    const r = await api.run(state.session, n);
    state.maxCycle = r.cycle;
    state.cycle = r.cycle;
    state.lastRun = describeRun(r);
    setStatus(state.lastRun);
    setCycleBounds();
    syncToTab();
    await refreshPane();
  } catch (e) { setStatus('error: ' + e.message); }
}

/*  Unsaved buffers survive a reload. The editor is where a half-written program
 *  lives, and a reload — or a crash, or a closed laptop — used to take it. Only
 *  the text and the name: a handle to a file on disk cannot be serialised, and
 *  a run can be repeated. */
const BUFKEY = 'lps.buffers';
function saveBuffers() {
  try {
    const out = tabs.allTabs()
      .filter((t) => t.dirty && t.model)
      .map((t) => ({ name: t.name, text: t.model.getValue() }));
    localStorage.setItem(BUFKEY, JSON.stringify(out.slice(0, 12)));
  } catch { /* quota, private mode — losing the backup is not worth an error */ }
}
function restoreBuffers() {
  let saved = [];
  try { saved = JSON.parse(localStorage.getItem(BUFKEY) || '[]'); } catch { return; }
  if (!saved.length) return;
  for (const b of saved) tabs.openTab(b.text, b.name, { dirty: true });
  setStatus(`restored ${saved.length} unsaved buffer${saved.length > 1 ? 's' : ''}`);
}
window.addEventListener('beforeunload', (e) => {
  saveBuffers();
  if (tabs.allTabs().some((t) => t.dirty)) { e.preventDefault(); e.returnValue = ''; }
});

boot();

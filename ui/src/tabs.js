/* tabs.js — several files open at once (VS Code's shape, not its size).
 *
 * The IDE used to hold exactly one buffer. Everything to the right of the
 * splitter — the timeline, the scene, the assistant, the live session — was
 * therefore about "the program", singular, and switching examples threw the
 * previous run away. Comparing two programs meant two browser windows.
 *
 * A tab owns a Monaco model *and* the run made from it: the session, the
 * program id, the cycle you were looking at, the profile the server returned.
 * Switching tabs restores all of it, so the right-hand panes are always about
 * the file whose tab is lit. Monaco keeps markers per model, so diagnostics
 * follow their own file without being re-fetched.
 */

let monaco = null;
let editor = null;
let onSwitch = null;
let seq = 0;

const tabs = [];
let activeId = null;

export function initTabs(m, ed, cb) { monaco = m; editor = ed; onSwitch = cb; }

/*  Setting a model's value fires the same change event a keystroke does, and
 *  the editor cannot tell them apart — so it has to be told. Without this, a
 *  file is dirty the moment it is opened. */
let loading = 0;
export const isLoading = () => loading > 0;
function quietly(fn) {
  loading++;
  try { return fn(); } finally { setTimeout(() => { loading--; }, 0); }
}

export const allTabs = () => tabs;
export const activeTab = () => tabs.find((t) => t.id === activeId) || null;

/** The per-file state the rest of the IDE reads. Kept on the tab, mirrored on
 *  `state` while the tab is active — mirroring rather than rewriting every
 *  reader is the whole reason this file is short. */
function blank(name, text, syntax) {
  return {
    id: 'tab' + (++seq),
    name,
    model: quietly(() => monaco.editor.createModel(text, languageFor(syntax))),
    viewState: null,
    handle: null,
    dirty: false,
    session: null,
    program: null,
    lastRun: null,
    cycle: 0,
    maxCycle: 0,
    profile: null,
    live: null,
    le: null,              // for a .le tab: its generated program and provenance
    origin: null,          // set when the file came in through a converter
    original: null,        // …and the text it was converted *from*
    runs: 0,
    thisRun: null,
    prevRun: null,
  };
}

export function openTab(text, name, { handle = null, origin = null, original = null,
                                      activate = true, dirty = false } = {}) {
  const t = blank(name || 'untitled.lps', text, syntaxOf(name || ''));
  t.handle = handle;
  t.origin = origin;
  t.original = original;
  t.dirty = dirty;
  tabs.push(t);
  if (activate) setActive(t.id);
  renderTabs();
  return t;
}

/** Reuse an untitled, unmodified, empty tab rather than piling them up. */
export function openOrReuse(text, name, opts) {
  const cur = activeTab();
  if (cur && !cur.dirty && !cur.session && cur.model.getValue().trim() === '') {
    quietly(() => cur.model.setValue(text));
    cur.name = name || cur.name;
    cur.handle = opts?.handle || null;
    cur.origin = opts?.origin || null;
    cur.original = opts?.original || null;
    monaco.editor.setModelLanguage(cur.model, languageFor(syntaxOf(cur.name)));
    renderTabs();
    onSwitch?.(cur);
    return cur;
  }
  return openTab(text, name, opts);
}

export function setActive(id) {
  const cur = activeTab();
  if (cur && cur.id === id) return cur;
  if (cur) cur.viewState = editor.saveViewState();
  activeId = id;
  const t = activeTab();
  if (!t) return null;
  editor.setModel(t.model);
  if (t.viewState) editor.restoreViewState(t.viewState);
  editor.focus();
  renderTabs();
  onSwitch?.(t);
  return t;
}

export function closeTab(id) {
  const i = tabs.findIndex((t) => t.id === id);
  if (i < 0) return;
  const t = tabs[i];
  if (t.dirty && !confirm(`${t.name} has unsaved changes. Close it anyway?`)) return;
  t.model.dispose();
  tabs.splice(i, 1);
  if (activeId === id) {
    activeId = null;
    if (tabs.length) setActive(tabs[Math.min(i, tabs.length - 1)].id);
    else openTab('maxTime(10).\n\n', 'untitled.lps');
  }
  renderTabs();
}

/*  Logical English has a mode of its own now, built at run time from LE2's
 *  lexicon (le-language.js). It used to open as plain text, which is what an
 *  editor offers a file it has nothing to say about. */
const languageFor = (syntax) => (syntax === 'le' ? 'logicalenglish' : 'lps');

export const syntaxOf = (name) =>
  /\.(lpsw|_\.P|P)$/i.test(name) ? 'internal' : /\.le$/i.test(name) ? 'le' : 'legacy';

/*  The two halves of a Logical English program.
 *
 *  `foo.le` and `foo.lps` compile together, `.le` first — the escape hatch of
 *  docs/user/reference/le-for-lps.md §7, where `display/2`, Prolog and the real-time
 *  plumbing go, since they are not Logical English and gain nothing from being
 *  written as if they were. The CLI finds the companion on disk beside the
 *  document; a browser has no disk to look on, so here the pairing is by name
 *  among the tabs that are open, and the pair travels to the server together.
 *
 *  It works from either half: editing the companion and pressing Run runs the
 *  program, which is the whole program and not the file with the display
 *  clauses in it. */
export const companionNameFor = (name) => name.replace(/\.le$/i, '') + '.lps';
export const tabNamed = (name) => tabs.find((t) => t.name === name) || null;
const baseOf = (name) => name.replace(/\.(le|lps)$/i, '');

export function lePair(tab) {
  const t = tab || activeTab();
  if (!t) return null;
  if (syntaxOf(t.name) === 'le') return { le: t, lps: tabNamed(companionNameFor(t.name)) };
  if (!/\.lps$/i.test(t.name)) return null;
  const le = tabs.find((x) => syntaxOf(x.name) === 'le' && baseOf(x.name) === baseOf(t.name));
  return le ? { le, lps: t } : null;
}

/* ---- the strip ----------------------------------------------------------- */

let host = null;
export function mountTabs(el) { host = el; renderTabs(); }

export function renderTabs() {
  if (!host) return;
  host.replaceChildren(...tabs.map((t) => {
    const b = document.createElement('div');
    b.className = 'filetab' + (t.id === activeId ? ' on' : '') + (t.dirty ? ' dirty' : '');
    b.title = t.origin ? `${t.name} — converted from ${t.origin}` : t.name;
    const label = document.createElement('span');
    label.className = 'ft-name';
    label.textContent = t.name;
    b.appendChild(label);
    if (t.session) {
      /*  Not another `•`. The unsaved-changes marker is a bullet (style.css,
       *  `.filetab.dirty`), and a file that had been run *and* edited grew two
       *  identical dots side by side meaning entirely different things — the
       *  first reading of which is always "why is it twice as unsaved". A
       *  triangle says "there is a run here you can play". */
      const dot = document.createElement('span');
      dot.className = 'ft-ran';
      dot.title = 'this file has a run you can look at';
      dot.textContent = '▸';
      b.appendChild(dot);
    }
    const x = document.createElement('button');
    x.className = 'ft-close'; x.textContent = '×'; x.title = 'Close';
    x.addEventListener('click', (e) => { e.stopPropagation(); closeTab(t.id); });
    b.appendChild(x);
    b.addEventListener('click', () => setActive(t.id));
    b.addEventListener('auxclick', (e) => { if (e.button === 1) closeTab(t.id); });
    return b;
  }));
  const plus = document.createElement('button');
  plus.className = 'ft-new'; plus.textContent = '+'; plus.title = 'New file';
  plus.addEventListener('click', () => openTab('maxTime(10).\n\n', 'untitled.lps'));
  host.appendChild(plus);
}

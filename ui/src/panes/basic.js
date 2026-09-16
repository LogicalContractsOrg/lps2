/* basic.js — the panes that are readings of the trace: timeline (§I.10.2),
 * state changes (§I.10.3), explanations (§I.10.5) and the internal syntax.
 *
 * Nothing here re-runs anything or re-derives anything. Every pane is a view
 * of a record the engine already emitted, which is what makes them trustworthy
 * after an incident — the honest answer to a question the trace cannot settle
 * is "not recorded", never a plausible reconstruction.
 */
import { mountViewport } from '../viewport.js';
import { askable } from '../why.js';

const NS = 'http://www.w3.org/2000/svg';
const svg = (tag, attrs = {}) => {
  const e = document.createElementNS(NS, tag);
  for (const [k, v] of Object.entries(attrs)) e.setAttribute(k, v);
  return e;
};
export const el = (tag, attrs = {}, ...kids) => {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs)) {
    if (k === 'class') e.className = v;
    else if (k === 'text') e.textContent = v;
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else e.setAttribute(k, v);
  }
  for (const k of kids) if (k) e.appendChild(typeof k === 'string' ? document.createTextNode(k) : k);
  return e;
};
export const empty = (pane, msg) => pane.replaceChildren(el('p', { class: 'empty', text: msg }));

/* ---- timeline (§I.10.2) --------------------------------------------------
   One lane per fluent, showing the intervals it holds over; one lane for
   events and one for composite events. The `.lpst` structure is already this
   shape, so nothing is instrumented for the picture's sake.                */
export function renderTimeline(pane, data, cursor, onSeek) {
  const lanes = data.fluents || [];
  if (!lanes.length && !(data.events || []).length) {
    return empty(pane, 'Run a program to see its timeline.');
  }
  const max = Math.max(1, data.cycles || 1);
  const LW = 220, RH = 22, ROW = 18;
  const x = (c) => LW + c * 44;

  /*  Where each event goes.
   *
   *  The first version fanned a cycle's items around its tick 13 pixels apart
   *  and wrote the term next to each: two events in one cycle — which is every
   *  cycle of the goat — printed one label over the other. Terms are 30 to 40
   *  characters and a cycle is 44 pixels wide, so no arrangement that labels
   *  every dot in a single row can work.
   *
   *  So pack: greedy first fit into as many rows as it takes, a label starting
   *  at its own tick and the next row opening only when the current one is
   *  still occupied. A quiet run stays one row tall; a busy one grows.        */
  const packStrip = (cells) => {
    const rowEnd = [], placed = [];
    for (const cell of cells || []) {
      for (const item of cell.items || []) {
        const s = x(cell.cycle) - 6;
        const e = s + 18 + item.length * 6.2;
        let r = rowEnd.findIndex((end) => end <= s);
        if (r < 0) { r = rowEnd.length; rowEnd.push(0); }
        rowEnd[r] = e;
        placed.push({ cycle: cell.cycle, item, row: r });
      }
    }
    return { placed, rows: Math.max(1, rowEnd.length), right: Math.max(0, ...rowEnd) };
  };
  //  A refused call (an observed event an integrity constraint refused — a
  //  revert, in a contract) is drawn in the events strip too, crossed out: it
  //  was made, and it did not happen.
  const refusedCells = (data.refused || []).map((r) => ({ cycle: r.cycle, items: r.items.map((i) => '✗ ' + i) }));
  const refusedWhy = new Map();
  for (const r of data.refused || []) for (const i of r.items) refusedWhy.set(`${r.cycle}|✗ ${i}`, r.conditions);
  const ev = packStrip([...(data.events || []), ...refusedCells]), cp = packStrip(data.composites);
  //  A lane with nothing in it is a labelled empty row and a claim that the
  //  program has composite events. Most do not; the row was always drawn.
  const hasComposites = cp.placed.length > 0;

  //  A fluent declared with a default (`; 0 by default`) holds it for every
  //  key that has no lane above: one dashed line per such fluent says so,
  //  over the whole run, instead of a lane for each of infinitely many keys.
  const defaults = data.defaults || [];
  const evY = 26 + (lanes.length + defaults.length) * RH;
  const cpY = evY + ev.rows * ROW + 6;
  const H = (hasComposites ? cpY + cp.rows * ROW : evY + ev.rows * ROW) + 24;
  const W = Math.max(LW + (max + 1) * 44 + 40, ev.right + 20, cp.right + 20);
  const root = svg('svg', { width: W, height: H, viewBox: `0 0 ${W} ${H}`, class: 'timeline' });

  for (let c = 0; c <= max; c++) {
    root.appendChild(svg('line', { x1: x(c), y1: 18, x2: x(c), y2: H - 20, class: 'grid' }));
    const t = svg('text', { x: x(c), y: 12, 'text-anchor': 'middle', class: 'axis' });
    t.textContent = c; root.appendChild(t);
  }

  lanes.forEach((lane, i) => {
    const y = 26 + i * RH;
    const label = svg('text', { x: LW - 8, y: y + 14, 'text-anchor': 'end', class: 'lane' });
    label.textContent = lane.fluent;
    label.appendChild(svg('title')).textContent = lane.fluent;
    root.appendChild(label);
    for (const iv of lane.intervals || []) {
      const from = iv.from, to = iv.to;
      const r = svg('rect', {
        x: x(from) - 4, y: y + 3, width: Math.max(8, x(to) - x(from) + 8), height: RH - 8,
        rx: 6, class: 'hold lps-fluent-bar',
      });
      r.appendChild(svg('title')).textContent =
        `${lane.fluent} — cycles ${from}…${to}   (right-click: why?)`;
      askable(r, { term: lane.fluent, kind: 'fluent', cycle: from });
      root.appendChild(r);
    }
  });

  defaults.forEach((d, i) => {
    const y = 26 + (lanes.length + i) * RH;
    const label = svg('text', { x: LW - 8, y: y + 14, 'text-anchor': 'end', class: 'lane default' });
    label.textContent = `every other: ${d}`;
    label.appendChild(svg('title')).textContent =
      `${d} — the default: every key with no fact of its own (no lane above) holds it`;
    root.appendChild(label);
    const r = svg('rect', {
      x: x(0) - 4, y: y + 3, width: x(max) - x(0) + 8, height: RH - 8,
      rx: 6, class: 'hold lps-default-bar',
    });
    r.appendChild(svg('title')).textContent =
      `${d} — the default, at every cycle, for every key with no fact of its own`;
    root.appendChild(r);
  });

  const strip = (packed, y, cls, name) => {
    const label = svg('text', { x: LW - 8, y: y + 13, 'text-anchor': 'end', class: 'lane strong' });
    label.textContent = name; root.appendChild(label);
    for (const { cycle, item, row } of packed.placed) {
      const cy = y + row * ROW + 9;
      const refused = refusedWhy.get(`${cycle}|${item}`);
      const g = svg('g', { class: refused !== undefined ? `${cls} refused` : cls });
      g.appendChild(svg('circle', { cx: x(cycle), cy, r: 5 }));
      const t = svg('text', { x: x(cycle) + 9, y: cy + 4, class: 'tick' });
      t.textContent = item;
      g.appendChild(t);
      if (refused !== undefined) {
        const term = item.replace(/^✗ /, '');
        g.appendChild(svg('title')).textContent =
          `${term} — made at cycle ${cycle} and refused: an integrity constraint held (${refused})   (right-click: why not?)`;
        askable(g, { term, kind: 'refused', cycle });
      } else {
        g.appendChild(svg('title')).textContent = `${item} — cycle ${cycle}   (right-click: why?)`;
        askable(g, { term: item, kind: cls === 'cp' ? 'event' : 'event', cycle });
      }
      root.appendChild(g);
    }
  };
  strip(ev, evY, 'ev', 'events');
  if (hasComposites) strip(cp, cpY, 'cp', 'composites');

  /*  A legend, because the shapes and the colours are a language of their own:
   *  a bar is a fluent holding over an interval, a dot is something that
   *  happened at an instant, and a dashed dot is a composite event. The colours
   *  are LPS1's (legacy_lps1/swish/web/lps/lps.css). */
  const key = svg('g', { class: 'tl-legend' });
  const keyItem = (dx, cls, shape, text) => {
    if (shape === 'bar') key.appendChild(svg('rect', { x: dx, y: H - 15, width: 22, height: 9, rx: 4, class: cls }));
    else key.appendChild(svg('circle', { cx: dx + 6, cy: H - 10, r: 5, class: cls }));
    const t = svg('text', { x: dx + 28, y: H - 7, class: 'axis' });
    t.textContent = text; key.appendChild(t);
  };
  keyItem(LW - 210, 'hold lps-fluent-bar', 'bar', 'fluent, over an interval');
  keyItem(LW - 40, 'ev-key', 'dot', 'event or action');
  if (refusedCells.length) keyItem(LW + 100, 'refused-key', 'dot', 'refused by a constraint');
  if (defaults.length) keyItem(LW + (refusedCells.length ? 280 : 100) + (hasComposites ? 180 : 0),
                               'hold lps-default-bar', 'bar', 'a default (no fact stored)');
  if (hasComposites) keyItem(LW + (refusedCells.length ? 280 : 100), 'cp-key', 'dot', 'composite event');
  root.appendChild(key);

  if (cursor != null) {
    root.appendChild(svg('line', { x1: x(cursor), y1: 14, x2: x(cursor), y2: H - 18, class: 'cursor' }));
  }
  root.addEventListener('click', (e) => {
    if (!onSeek) return;
    const box = root.getBoundingClientRect();
    const rel = (e.clientX - box.left) * (W / box.width) - LW;
    const c = Math.round(rel / 44);
    if (c >= 0 && c <= max) onSeek(c);
  });

  //  A chart is read from the top down, so what spare height there is goes
  //  below it rather than half above and half below.
  const vp = mountViewport(pane, root, { onFit: () => vp.fit(W, H, 0.4, 'top') });
  vp.fit(W, H, 0.4, 'top');
  return vp;
}

/* ---- state changes (§I.10.3) --------------------------------------------
   What was initiated, terminated, updated and persisted in one cycle — and,
   the part the old system never had, *which causal law* was responsible.   */
export function renderChanges(pane, data, cycle, onSeek, near, onSource, nothingEverChanged) {
  const rows = [];
  const add = (kind, list) => (list || []).forEach((c) => rows.push({ kind, ...c }));
  add('initiated', data.initiated);
  add('terminated', data.terminated);
  add('updated', data.updated);
  if (!rows.length) {
    /*  "Nothing changed at cycle 4." is true and unhelpful: the reader is
     *  looking for the cycle where something *did*. Say which ones those are,
     *  and make them destinations — in both directions, because a run lands on
     *  its last cycle and the interesting ones are usually behind it. */
    const box = el('div', { class: 'empty' }, el('p', { text: `Nothing changed at cycle ${data.cycle}.` }));
    if (nothingEverChanged) {
      box.appendChild(el('p', {
        class: 'muted',
        text: 'Nothing changed in any cycle of this run. That is not a broken pane: '
          + 'a program whose fluents only move when an event arrives does nothing at all '
          + 'in a batch run. Start a Live session and send it one.',
      }));
    } else if (onSeek) {
      const actions = el('div', { class: 'empty-actions' });
      const jump = (c, label) => {
        const b = el('button', { text: label });
        b.addEventListener('click', () => onSeek(c));
        actions.appendChild(b);
      };
      if (near?.prev != null) jump(near.prev, `◀ cycle ${near.prev}, the last one that changed`);
      if (near?.next != null) jump(near.next, `cycle ${near.next}, the next one that changed ▶`);
      if (actions.childElementCount) box.appendChild(actions);
    }
    return pane.replaceChildren(box);
  }
  //  Grouped by the law that did it: the question after "what changed" is
  //  always "which rule", and the answer reads better as a heading than as a
  //  column repeated down the table.
  rows.sort((a, b) => String(a.source || '').localeCompare(String(b.source || ''))
    || a.kind.localeCompare(b.kind));
  const table = el('table', { class: 'changes' },
    el('thead', {}, el('tr', {},
      el('th', { text: '' }), el('th', { text: 'fluent' }),
      el('th', { text: 'because of' }), el('th', { text: 'law' }))));
  const body = el('tbody');
  const at = cycle ?? data.cycle;
  let lastSource = null;
  for (const r of rows) {
    if (r.source !== lastSource) {
      lastSource = r.source;
      const label = sourceLabel(r.source) || 'no recorded law';
      const head = el('span', { class: 'law', text: label, title: r.source || '' });
      const line = firstSource(r.source);
      if (line && onSource) {
        head.classList.add('has-source');
        head.title = `go to line ${line}`;
        head.addEventListener('click', () => onSource(line));
      }
      body.appendChild(el('tr', { class: 'lawgroup' }, el('td', { colspan: '4' }, head)));
    }
    /*  An update prints as `Old-New`, and the two halves are opposite
     *  questions: at this cycle the *new* one holds and the *old* one does
     *  not. Making the whole cell one target meant right-clicking anywhere in
     *  it asked about the old value and got "does not hold" — technically
     *  true, and never what was wanted. Each half is its own target. */
    const fluentCell = el('td', { class: 'fluent' });
    const split = balancedSplit(r.fluent, '-');
    if (r.kind === 'updated' && split > 0) {
      const oldT = r.fluent.slice(0, split), newT = r.fluent.slice(split + 1);
      const o = el('span', { text: oldT, title: `right-click: why did ${oldT} stop?` });
      askable(o, { term: oldT, kind: 'stopped', cycle: at });
      const nn = el('span', { text: newT, title: `right-click: why does ${newT} hold?` });
      askable(nn, { term: newT, kind: 'fluent', cycle: at });
      fluentCell.append(o, el('span', { class: 'muted', text: ' → ' }), nn);
    } else {
      const one = el('span', { text: r.fluent, title: 'right-click: why?' });
      askable(one, { term: r.fluent, kind: r.kind === 'terminated' ? 'stopped' : 'fluent', cycle: at });
      fluentCell.appendChild(one);
    }
    const eventCell = el('td', { class: 'event', text: r.action || '' });
    if (r.action) {
      eventCell.title = 'right-click: why?';
      askable(eventCell, { term: happenedTerm(r.action), kind: 'event', cycle: at });
    }
    body.appendChild(el('tr', { class: r.kind },
      el('td', { class: 'kind', text: r.kind }),
      fluentCell, eventCell,
      el('td', { class: 'law muted', text: '' })));
  }
  table.appendChild(body);
  const persisted = el('p', { class: 'empty' });
  if ((data.persisted || []).length) {
    persisted.appendChild(el('span', { text: 'persisted: ' }));
    (data.persisted || []).forEach((f, i) => {
      if (i) persisted.appendChild(el('span', { text: ', ' }));
      const s2 = el('span', { text: f, title: 'right-click: why?' });
      askable(s2, { term: f, kind: 'fluent', cycle: at });
      persisted.appendChild(s2);
    });
  } else persisted.textContent = 'nothing persisted';
  pane.replaceChildren(table, persisted);
}

/*  The changes pane prints an event as `happens(row(north,south),2,3)`, which
 *  is readable and is not a question: strip it back to the term. */
function happenedTerm(s) {
  const m = /^happens\((.*),\s*\d+\s*,\s*\d+\)$/.exec(s.trim());
  return m ? m[1] : s;
}
function balancedSplit(s, ch) {
  let d = 0;
  for (let i = 0; i < s.length; i++) {
    if (s[i] === '(' || s[i] === '[') d++;
    else if (s[i] === ')' || s[i] === ']') d--;
    else if (s[i] === ch && d === 0) return i;
  }
  return -1;
}

/*  `src(File,Line,Col,Kind)` is the joint provenance term of the LE interface
 *  (docs/dev/le-lps-interface.md), and it is the right thing to *carry*. It is not
 *  the right thing to put in a table cell: what the reader wants is the line,
 *  and the file only when it is not the one in front of them. The whole term
 *  stays in the tooltip. */
function sourceLabel(src) {
  if (!src) return '';
  const m = /^src\(([^,]*),\s*(\d+)/.exec(src);
  if (!m) return src;
  const [, file, line] = m;
  return file === 'buffer' || file === 'user' ? `line ${line}` : `${file}:${line}`;
}

/* ---- explanations (§I.10.5) ---------------------------------------------- */
export function renderExplanation(pane, expl, onSource) {
  const box = el('div', { class: 'explanation' });
  box.appendChild(el('div', { class: 'verdict ' + (expl.verdict || ''), text: expl.verdict || '' }));
  const tree = (node, depth) => {
    const label = `${node.label || ''}${node.detail ? ' — ' + node.detail : ''}`;
    const line = firstSource(label);
    const d = el('div', {
      class: 'node' + (line ? ' has-source' : ''),
      style: `margin-left:${depth * 18}px`,
      title: line ? `go to line ${line}` : '',
    },
    el('span', { class: 'label', text: node.label || '' }),
    node.detail ? el('span', { class: 'detail', text: ' — ' + node.detail }) : null);
    //  A node that names a clause is a node you want to be looking at. The
    //  provenance is already in the text — `src(buffer,24,0,internal)` — so
    //  the only thing missing was making it a destination.
    if (line && onSource) d.addEventListener('click', () => onSource(line));
    box.appendChild(d);
    (node.children || []).forEach((c) => tree(c, depth + 1));
  };
  if (expl.tree) tree(expl.tree, 0);
  else box.appendChild(el('p', { class: 'empty', text: 'nothing recorded' }));
  pane.replaceChildren(box);
}

//  `src(File,Line,Col,Kind)` anywhere in a node's text.
function firstSource(text) {
  const m = /src\([^,]*,\s*(\d+)\s*,/.exec(text || '');
  return m ? Number(m[1]) : null;
}

/* ---- internal syntax -----------------------------------------------------
   The §I.3 representation the compiler actually consumes. Two affordances it
   was missing: a copy button (this text is the thing people paste into a bug
   report), and a way back to the surface. The dump carries no provenance, so
   the jump is a *search* for a clause head naming the same predicate — which
   is what it says on the row, because a link that pretends to be exact and is
   not is worse than one that admits what it does.                            */
export function renderInternal(pane, text, onFind) {
  const pre = el('pre', { class: 'internal' });
  for (const line of (text || '').split('\n')) {
    const row = el('div', { class: 'iline', text: line });
    const name = /^\s*([a-z_][A-Za-z0-9_]*)\s*\(/.exec(line)?.[1];
    const inner = /\b(?:happens|holds)\(\s*(?:not\()?\s*([a-z_][A-Za-z0-9_]*)/.exec(line)?.[1];
    const target = inner || name;
    if (target && onFind) {
      row.classList.add('has-source');
      row.title = `find ${target} in the source`;
      row.addEventListener('click', () => onFind(target));
    }
    pre.appendChild(row);
  }
  //  "Copy" alone, floating at the top right of a wall of Prolog, does not say
  //  what it would put on the clipboard.
  const copy = el('button', { class: 'copy', text: 'Copy this text' });
  copy.title = 'Copy the whole internal-syntax program — this is what a bug report wants';
  copy.addEventListener('click', () => {
    navigator.clipboard?.writeText(text || '');
    copy.textContent = 'Copied';
    setTimeout(() => { copy.textContent = 'Copy this text'; }, 1200);
  });
  pane.replaceChildren(el('div', { class: 'internal-head' },
    el('span', { class: 'muted', text: 'the §I.3 internal syntax the compiler consumes — click a line to find it in the source' }),
    copy), pre);
}


/* ---- the generated program, beside the English -------------------------- */

/*  A Logical English document compiles to LPS internal syntax, and the
 *  provenance array (§2 of the interface) says which *sentence* each generated
 *  term came from — by term index, in term order. So the two texts can be read
 *  together: clicking a term takes the editor to its sentence, and the line
 *  says which one it will be before you click.
 *
 *  Terms are counted, not parsed: a term ends at a full stop that ends a line,
 *  which is the shape LE2's writer emits and the same rule the internal reader
 *  uses. A line that is not the start of a term inherits the term it is inside.
 */
export function renderGenerated(pane, le, onSource) {
  const lines = (le.lps || '').split('\n');
  const byIndex = new Map((le.provenance || []).map((p) => [p.index, p]));
  const pre = el('pre', { class: 'internal generated' });
  let term = 0, inTerm = false;
  for (const text of lines) {
    const row = el('div', { class: 'iline', text });
    const trimmed = text.trim();
    if (trimmed && !trimmed.startsWith('%')) {
      const prov = byIndex.get(term);
      if (prov && prov.line) {
        row.classList.add('has-source');
        row.title = `from line ${prov.line} of the document`;
        row.addEventListener('click', () => onSource(prov.line));
        row.appendChild(el('span', { class: 'prov muted', text: `  ← line ${prov.line}` }));
      }
      inTerm = true;
      if (/\.\s*$/.test(trimmed)) { term += 1; inTerm = false; }
    }
    pre.appendChild(row);
  }
  if (inTerm) { /* an unterminated last term; nothing to count */ }
  pane.replaceChildren(
    el('div', { class: 'internal-head' },
      el('span', { class: 'muted', text: 'generated from the Logical English — read only' })),
    pre);
}

/* basic.js — the panes that are readings of the trace: timeline (§I.10.2),
 * state changes (§I.10.3), explanations (§I.10.5) and the internal syntax.
 *
 * Nothing here re-runs anything or re-derives anything. Every pane is a view
 * of a record the engine already emitted, which is what makes them trustworthy
 * after an incident — the honest answer to a question the trace cannot settle
 * is "not recorded", never a plausible reconstruction.
 */
import { mountViewport } from '../viewport.js';

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
  const ev = packStrip(data.events), cp = packStrip(data.composites);

  const evY = 26 + lanes.length * RH;
  const cpY = evY + ev.rows * ROW + 6;
  const H = cpY + cp.rows * ROW + 24;
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
        rx: 6, class: 'hold',
      });
      r.appendChild(svg('title')).textContent = `${lane.fluent} — cycles ${from}…${to}`;
      root.appendChild(r);
    }
  });

  const strip = (packed, y, cls, name) => {
    const label = svg('text', { x: LW - 8, y: y + 13, 'text-anchor': 'end', class: 'lane strong' });
    label.textContent = name; root.appendChild(label);
    for (const { cycle, item, row } of packed.placed) {
      const cy = y + row * ROW + 9;
      const g = svg('g', { class: cls });
      g.appendChild(svg('circle', { cx: x(cycle), cy, r: 5 }));
      const t = svg('text', { x: x(cycle) + 9, y: cy + 4, class: 'tick' });
      t.textContent = item;
      g.appendChild(t);
      g.appendChild(svg('title')).textContent = `${item} — cycle ${cycle}`;
      root.appendChild(g);
    }
  };
  strip(ev, evY, 'ev', 'events');
  strip(cp, cpY, 'cp', 'composites');

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

  const vp = mountViewport(pane, root, { onFit: () => vp.fit(W, H) });
  vp.fit(W, H);
  return vp;
}

/* ---- state changes (§I.10.3) --------------------------------------------
   What was initiated, terminated, updated and persisted in one cycle — and,
   the part the old system never had, *which causal law* was responsible.   */
export function renderChanges(pane, data) {
  const rows = [];
  const add = (kind, list) => (list || []).forEach((c) => rows.push({ kind, ...c }));
  add('initiated', data.initiated);
  add('terminated', data.terminated);
  add('updated', data.updated);
  if (!rows.length) {
    return empty(pane, `Nothing changed at cycle ${data.cycle}.`);
  }
  const table = el('table', { class: 'changes' },
    el('thead', {}, el('tr', {},
      el('th', { text: '' }), el('th', { text: 'fluent' }),
      el('th', { text: 'because of' }), el('th', { text: 'law' }))));
  const body = el('tbody');
  for (const r of rows) {
    body.appendChild(el('tr', { class: r.kind },
      el('td', { class: 'kind', text: r.kind }),
      el('td', { class: 'fluent', text: r.fluent }),
      el('td', { class: 'event', text: r.action || '' }),
      el('td', { class: 'law', text: sourceLabel(r.source), title: r.source || '' })));
  }
  table.appendChild(body);
  const persisted = (data.persisted || []).join(', ');
  pane.replaceChildren(table,
    el('p', { class: 'empty', text: persisted ? `persisted: ${persisted}` : 'nothing persisted' }));
}

/*  `src(File,Line,Col,Kind)` is the joint provenance term of the LE interface
 *  (docs/le_lps_interface.md), and it is the right thing to *carry*. It is not
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
export function renderExplanation(pane, expl) {
  const box = el('div', { class: 'explanation' });
  box.appendChild(el('div', { class: 'verdict ' + (expl.verdict || ''), text: expl.verdict || '' }));
  const tree = (node, depth) => {
    const d = el('div', { class: 'node', style: `margin-left:${depth * 18}px` },
      el('span', { class: 'label', text: node.label || '' }),
      node.detail ? el('span', { class: 'detail', text: ' — ' + node.detail }) : null);
    box.appendChild(d);
    (node.children || []).forEach((c) => tree(c, depth + 1));
  };
  if (expl.tree) tree(expl.tree, 0);
  else box.appendChild(el('p', { class: 'empty', text: 'nothing recorded' }));
  pane.replaceChildren(box);
}

/* ---- internal syntax ----------------------------------------------------- */
export function renderInternal(pane, text) {
  pane.replaceChildren(el('pre', { class: 'internal', text: text || '' }));
}

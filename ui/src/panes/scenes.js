/* scenes.js — the run as a STRIP of pictures (AnimationPlan.md §7).
 *
 * A scene pane draws one canvas and redraws it per cycle: it answers "what is
 * true now?". A reader who asks "what happened?" wants the other thing — the
 * run laid out, one picture per moment at which the picture became a different
 * picture, with what moved the story on written between them.
 *
 * Which moments those are is not guessed here: the server's `focus` (§5) says
 * which cycles are worth a frame, and `scenes` returns one scene per frame
 * with the events and the state changes that got there. So the strip and the
 * slider's landmarks and the prompt the assistant is given all agree about
 * what mattered in this run, because all three read the same answer.
 *
 * Two dimensions and three are the same strip. A 2D frame is a small Konva
 * stage; a 3D frame is one <img>, rendered by a single reused WebGL context
 * (snapshot3d) — a dozen live contexts is not a way to draw a dozen
 * thumbnails.
 *
 * The strip is the map; the canvas is the place. Clicking a frame goes to that
 * cycle and opens the full scene there.
 */
import Konva from 'konva';
import { sceneGroup, fitGroupTo, isTitle } from './scene2d.js';
import { snapshot3d } from './scene3d.js';
import { emptyWithOffer, sceneLegend } from './shared.js';
import { sayTerm, sayPredicate } from '../le-words.js';

const FRAME_W = 220;
const FRAME_H = 150;

/*  What happened on the way to this frame, in words.
 *
 *  Computed, not written by a model: the events recorded at that cycle and the
 *  fluents that began, ended or changed value with them are exactly what the
 *  trace has, and a sentence made of them cannot say anything the run did not
 *  do. (A model's own wording could be layered on top later; it would have to
 *  be checked against this.) */
function caption(f) {
  const bits = [];
  //  NOT the events: they are written on the arrow that leads to this frame,
  //  and a caption that repeats them says everything twice (R12). What is
  //  left is what the events did — which is the half the arrow cannot show.
  if (f.began?.length) bits.push('+ ' + f.began.map(say).join(', '));
  if (f.ended?.length) bits.push('− ' + f.ended.map(say).join(', '));
  if (f.updated?.length) bits.push('→ ' + f.updated.map((u) => String(u).split('-').map(say).join(' → ')).join(', '));
  if (!bits.length) return f.cycle === 0 ? 'the state it starts in' : 'nothing changed here';
  return bits.join('  ·  ');
}

/*  A term in the program's own words, when the program is one whose words we
 *  have: a Logical English document declares `*an object* is at *a place*;
 *  known as loc`, and that is the sentence the reader wrote. Falls back to the
 *  term (the review's R5). */
const say = (t) => sayTerm(String(t));

function el(tag, attrs, ...kids) {
  const n = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (k === 'class') n.className = v;
    else if (k === 'text') n.textContent = v;
    else if (k === 'title') n.title = v;
    else n.setAttribute(k, v);
  }
  for (const c of kids) if (c) n.appendChild(c);
  return n;
}

/**
 * Draw the strip into `pane`.
 *   data   the `scenes` reply: {kind, cycles, frames:[…], more}
 *   opts   {cycle, onZoom(cycle), onSingle(), scroll, onScroll(x)}
 */
export function renderSceneStrip(pane, data, { cycle, onZoom, onSingle, scroll, onScroll } = {}) {
  const frames = data.frames || [];
  const three = data.kind === '3d';
  pane.replaceChildren();
  pane.classList.add('strip-host');
  if (!frames.length) {
    pane.appendChild(el('p', { class: 'empty', text: 'Nothing to draw: this run has no picture at any cycle.' }));
    return null;
  }
  //  A program with no mapping for THIS dimension draws nothing in every
  //  frame, and the answer to that is the offer the single pane makes, not a
  //  row of empty cards.
  if (!frames.some((f) => (f.items || []).length || (f.timeless || []).length)) {
    emptyWithOffer(pane, three ? 'display3d/2' : 'display/2',
      three ? 'Animate in 3D' : 'Animate in 2D', three ? 'animate-3d' : 'animate-2d');
    return null;
  }

  const head = el('div', { class: 'strip-head' });
  //  The scene's title, once — each frame drops it (sceneGroup's skipTitle).
  const title = titleOf(frames[0]);
  if (title) head.appendChild(el('strong', { text: title }));
  head.appendChild(el('span', {
    class: 'muted',
    text: `${frames.length} scene${frames.length === 1 ? '' : 's'} of a ${data.cycles}-cycle run`
      + (data.more ? ` (${data.more} more not shown)` : ''),
  }));
  head.appendChild(el('span', {
    class: 'muted strip-hint',
    text: 'one picture per moment at which it changed — click one to open it',
  }));
  pane.appendChild(head);

  const strip = el('div', { class: 'strip' });
  pane.appendChild(strip);
  //  Where the reader was. Coming back from a frame at cycle 30 to the
  //  beginning of the run is coming back to the wrong place (R3).
  strip.addEventListener('scroll', () => onScroll && onScroll(strip.scrollLeft));

  /*  One window on the world for the whole strip: the union of what every
   *  frame draws. Frames fitted to their own contents would each fill their
   *  card, and a thing that stayed exactly where it was would appear to move
   *  and change size from one picture to the next. */
  const drawn = [];
  frames.forEach((f, i) => {
    if (i > 0) {
      //  What moved the story on, between the two pictures it moved between.
      strip.appendChild(arrowTo(f));
    }
    const card = el('div', {
      class: 'strip-frame' + (f.cycle === cycle ? ' on' : '') + (f.returns ? ' returns' : ''),
      //  The whole caption on hover: the card shows as much of it as fits, and
      //  a thumbnail is exactly where a reader wants the rest without opening
      //  anything.
      title: (f.returns
        ? `cycle ${f.cycle} — a state this run has been in before`
        : `cycle ${f.cycle}`) + `\n${caption(f)}`,
    });
    card.addEventListener('click', () => onZoom && onZoom(f.cycle));
    const host = el('div', { class: 'strip-canvas' });
    card.appendChild(host);
    card.appendChild(el('div', { class: 'strip-cycle', text: `cycle ${f.cycle}` }));
    card.appendChild(el('div', { class: 'strip-caption', text: caption(f) }));
    strip.appendChild(card);
    const d = drawFrame(host, f, data.kind);
    if (d) drawn.push(d);
  });
  stripTools(pane, strip, { frames, title, onSingle });
  //  The vocabulary of the pictures, once for the whole strip: a single scene
  //  has a legend and the strip had none (R11).
  sceneLegend(pane, legendOf(frames));
  //  Now that every frame is built, fit them all to the one box.
  if (data.kind !== '3d' && drawn.length) {
    const union = drawn.reduce((a, d) => {
      const b = d.content.getClientRect({ relativeTo: d.content });
      if (!b.width && !b.height) return a;
      if (!a) return { ...b };
      const x = Math.min(a.x, b.x), y = Math.min(a.y, b.y);
      return { x, y,
        width: Math.max(a.x + a.width, b.x + b.width) - x,
        height: Math.max(a.y + a.height, b.y + b.height) - y };
    }, null);
    for (const d of drawn) {
      fitGroupTo(d.stage, d.content, union || { x: 0, y: 0, width: 1, height: 1 }, 10, 2);
      d.layer.batchDraw();
    }
  }
  //  Put the reader back where they were, and say that there is more to the
  //  side when there is (R12: nothing said the strip scrolled).
  if (scroll) strip.scrollLeft = scroll;
  requestAnimationFrame(() => {
    if (strip.scrollWidth > strip.clientWidth + 4) {
      head.appendChild(el('span', { class: 'muted strip-hint', text: '↔ it scrolls sideways' }));
    }
  });
  return { frames: frames.length };
}

/*  The arrow between two frames: what moved the story on, and a way to ask
    why it did.

    Two events and a count, not the twenty that a concurrent program can do in
    one cycle — five philosophers putting forks down made a column of text
    taller than the pictures it was between; the whole list is the arrow's
    tooltip. Each event is `askable`, which is all it takes for the IDE's own
    right-click ▸ *why?* to work here as it does in every other pane (the
    review's R11: the strip had no hover and no why). */
function arrowTo(f) {
  const evs = f.events || [];
  const arrow = el('div', { class: 'strip-arrow', title: evs.map(say).join('\n') });
  const lab = el('span', { class: 'strip-arrow-label' });
  if (!evs.length) lab.textContent = '…';
  evs.slice(0, 2).forEach((e, i) => {
    if (i) lab.appendChild(document.createTextNode(', '));
    const sp = el('span', { class: 'askable', text: say(e),
                            title: `${e}\n\nright-click to ask why it happened` });
    sp.dataset.lpsTerm = String(e);
    sp.dataset.lpsKind = 'event';
    sp.dataset.lpsCycle = String(f.cycle);
    lab.appendChild(sp);
  });
  if (evs.length > 2) lab.appendChild(document.createTextNode(`  · +${evs.length - 2} more`));
  arrow.appendChild(lab);
  return arrow;
}

//  The scene's own title, drawn once in the head instead of in every frame.
function titleOf(f) {
  const t = (f?.timeless || []).find(isTitle);
  return t ? String(t.content ?? '') : '';
}

/*  One row per fluent the run draws, in the colour it is drawn in — the same
 *  legend the single scene has, over the whole strip rather than one cycle,
 *  because a strip is read across its frames. */
function legendOf(frames) {
  const seen = new Map();
  for (const f of frames) {
    for (const i of f.items || []) {
      const name = String(i.ask || i.subject || '').replace(/\(.*$/, '');
      if (!name || seen.has(name)) continue;
      const p = i.props || {};
      const c = p.fillColor ?? p.color ?? p.strokeColor;
      seen.set(name, { colour: typeof c === 'string' ? c : '#888', label: sayPredicate(name) });
    }
  }
  return [...seen.values()];
}

/*  The strip's own toolbar (R11).
 *
 *  The single scene has PNG, Record, Compare and the two change buttons; the
 *  strip had nothing at all — not even a way out of it that did not go
 *  through another panel. Record and Compare belong to a canvas being
 *  scrubbed and are meaningless here; a picture of the whole strip is the one
 *  thing a strip can give that a scene cannot. */
function stripTools(pane, strip, { frames, title, onSingle }) {
  const old = pane.querySelector('.scene-tools');
  if (old) old.remove();
  const box = el('div', { class: 'scene-tools' });
  const mk = (label, tip, fn) => {
    const b = el('button', { text: label, title: tip });
    b.addEventListener('click', (e) => { e.stopPropagation(); fn(b); });
    box.appendChild(b);
    return b;
  };
  if (onSingle) {
    mk('◀ Single scene', 'Go back to one picture at a time, scrubbed with the slider',
       () => onSingle());
  }
  mk('PNG', 'Save the whole strip as one image', (b) => {
    try {
      const url = stripPng(strip, title);
      const a = document.createElement('a');
      a.href = url;
      a.download = `strip-${frames.length}-scenes.png`;
      a.click();
    } catch (e) { b.title = 'this browser could not compose the strip: ' + e.message; }
  });
  pane.appendChild(box);
}

/*  The strip, as one picture.
 *
 *  Composed from what the browser has already laid out: every frame is at a
 *  position the flex row chose, and each holds either a Konva canvas or a
 *  rendered <img>. So this paints rather than lays out — the picture cannot
 *  disagree with the strip it is a picture of.
 */
function stripPng(strip, title) {
  const css = getComputedStyle(strip);
  const fg = css.color || '#dfe3ea';
  const bg = getComputedStyle(document.body).backgroundColor || '#16181d';
  const top = title ? 24 : 4;
  const W = Math.max(strip.scrollWidth, 1), H = Math.max(strip.scrollHeight, 1) + top + 4;
  const c = document.createElement('canvas');
  const dpr = 2;
  c.width = W * dpr; c.height = H * dpr;
  const x = c.getContext('2d');
  x.scale(dpr, dpr);
  x.fillStyle = bg; x.fillRect(0, 0, W, H);
  x.textBaseline = 'top';
  if (title) {
    x.fillStyle = fg; x.font = '600 14px system-ui, sans-serif';
    x.fillText(title, 4, 4);
  }
  const at = (n) => ({ x: n.offsetLeft - strip.scrollLeft + strip.scrollLeft, y: n.offsetTop });
  for (const card of strip.querySelectorAll('.strip-frame')) {
    const p = at(card);
    const img = card.querySelector('canvas, img');
    if (img) {
      try { x.drawImage(img, p.x + 4, p.y + top + 4, FRAME_W, FRAME_H); } catch { /* tainted */ }
    }
    x.strokeStyle = 'rgba(128,128,128,.45)';
    x.strokeRect(p.x + 0.5, p.y + top + 0.5, card.offsetWidth - 1, card.offsetHeight - 1);
    let ty = p.y + top + FRAME_H + 10;
    x.fillStyle = 'rgba(128,140,160,.95)'; x.font = '11px system-ui, sans-serif';
    x.fillText(card.querySelector('.strip-cycle')?.textContent || '', p.x + 6, ty);
    ty += 14;
    x.fillStyle = fg; x.font = '12px system-ui, sans-serif';
    wrapText(x, card.querySelector('.strip-caption')?.textContent || '', p.x + 6, ty, FRAME_W - 8, 15);
  }
  for (const arrow of strip.querySelectorAll('.strip-arrow')) {
    const p = at(arrow);
    x.fillStyle = 'rgba(128,140,160,.95)';
    x.font = '15px system-ui, sans-serif';
    x.fillText('→', p.x + arrow.offsetWidth / 2 - 7, p.y + top);
    x.font = '11px system-ui, sans-serif';
    wrapText(x, arrow.textContent || '', p.x + 2, p.y + top + 20, arrow.offsetWidth - 4, 13, 'center');
  }
  return c.toDataURL('image/png');
}

//  Words, not characters: a line broken mid-word is how `transfer(far
//  iba,10,bob)` happened in the strip itself (R12).
function wrapText(x, text, x0, y0, w, lh, align) {
  const words = String(text).split(/\s+/).filter(Boolean);
  let line = '', y = y0;
  const put = (s) => {
    const dx = align === 'center' ? (w - x.measureText(s).width) / 2 : 0;
    x.fillText(s, x0 + Math.max(0, dx), y);
    y += lh;
  };
  for (const word of words) {
    const next = line ? line + ' ' + word : word;
    if (x.measureText(next).width > w && line) { put(line); line = word; } else line = next;
  }
  if (line) put(line);
}

//  One frame's picture. 2D draws it; 3D photographs it.
function drawFrame(host, f, kind) {
  if (kind === '3d') {
    try {
      const img = new Image();
      img.src = snapshot3d(f, FRAME_W, FRAME_H);
      img.className = 'strip-img';
      host.appendChild(img);
    } catch (e) {
      host.appendChild(el('p', { class: 'muted', text: 'could not draw this frame' }));
    }
    return null;
  }
  const stage = new Konva.Stage({ container: host, width: FRAME_W, height: FRAME_H });
  const layer = new Konva.Layer();
  const content = sceneGroup(f, () => layer.batchDraw(), { skipTitle: true });
  layer.add(content);
  stage.add(layer);
  return { stage, layer, content };
}

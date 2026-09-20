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
import { sceneGroup, fitGroupTo } from './scene2d.js';
import { snapshot3d } from './scene3d.js';
import { emptyWithOffer } from './shared.js';

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
  if (f.events?.length) bits.push(f.events.join(', '));
  if (f.began?.length) bits.push('+ ' + f.began.join(', '));
  if (f.ended?.length) bits.push('− ' + f.ended.join(', '));
  if (f.updated?.length) bits.push('→ ' + f.updated.map((u) => String(u).replace('-', ' → ')).join(', '));
  if (!bits.length) return f.cycle === 0 ? 'the state it starts in' : 'nothing changed here';
  return bits.join('  ·  ');
}

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
 *   opts   {cycle, onZoom(cycle)}
 */
export function renderSceneStrip(pane, data, { cycle, onZoom } = {}) {
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

  /*  One window on the world for the whole strip: the union of what every
   *  frame draws. Frames fitted to their own contents would each fill their
   *  card, and a thing that stayed exactly where it was would appear to move
   *  and change size from one picture to the next. */
  const drawn = [];
  frames.forEach((f, i) => {
    if (i > 0) {
      //  What moved the story on, between the two pictures it moved between.
      strip.appendChild(el('div', { class: 'strip-arrow' },
        el('span', { class: 'strip-arrow-label', text: (f.events || []).join(', ') || '…' })));
    }
    const card = el('div', {
      class: 'strip-frame' + (f.cycle === cycle ? ' on' : '') + (f.returns ? ' returns' : ''),
      title: f.returns
        ? `cycle ${f.cycle} — a state this run has been in before`
        : `cycle ${f.cycle}`,
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
  return { frames: frames.length };
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
  const content = sceneGroup(f, () => layer.batchDraw());
  layer.add(content);
  stage.add(layer);
  return { stage, layer, content };
}

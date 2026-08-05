/* scene2d.js — the animation pane, on Konva (M15a).
 *
 * The M10 pane drew SVG in sixty lines and degraded `star`, `line`, `path`,
 * `arc`, `regularPolygon` and text to ellipses. This one aims at parity with
 * the whole of legacy_lps1/swish/2dWord.md, because Konva's shape vocabulary
 * and paper.js's line up almost one to one — this is a re-hosting, not a
 * reinterpretation.
 *
 * Two behaviours are inherited from the old renderer rather than from the SVG
 * one, and both were bugs in the SVG one:
 *
 *   * **the origin is bottom left.** paper.js ran with an inverted view matrix
 *     and 2dWord.md documents the convention, so a scene written for the old
 *     renderer came out vertically mirrored in the M10 pane. Here the content
 *     layer is scaled by -1 in y and every text node is counter-flipped —
 *     which is precisely the `matrix.d = -1` fixup paper.js itself needed.
 *   * **only the first display/2 solution per subject is drawn**, as upstream
 *     does. The server sends what it finds; the choice belongs here.
 *
 * Motion between cycles is a Konva tween per object, keyed by the subject term,
 * so a fluent that moves slides instead of jumping. Objects that appear or
 * vanish fade.
 */
import Konva from 'konva';
import { showTip, emptyWithOffer, sceneLegend, sceneToolbar } from './shared.js';
import { resolveIcon } from '../icons.js';

const DUR = 0.35;

let stage = null, layer = null, content = null, prev = new Map(), lastPane = null;

const num = (v, d) => (typeof v === 'number' ? v : (typeof v === 'string' && v !== '' && !isNaN(+v) ? +v : d));
const pt = (p, keys) => { for (const k of keys) if (Array.isArray(p[k])) return p[k].map((n) => num(n, 0)); return null; };
const colour = (v, d) => (v === undefined || v === null ? d : Array.isArray(v)
  ? `rgb(${Math.round(num(v[0], 0) * 255)},${Math.round(num(v[1], 0) * 255)},${Math.round(num(v[2], 0) * 255)})`
  : String(v));

/** Every property the old renderer documented, mapped onto Konva's names. */
function common(p) {
  const o = {};
  if (p.fillColor !== undefined) o.fill = colour(p.fillColor);
  if (p.strokeColor !== undefined) o.stroke = colour(p.strokeColor);
  if (p.strokeWidth !== undefined) o.strokeWidth = num(p.strokeWidth, 1);
  else if (p.strokeColor !== undefined) o.strokeWidth = 1;
  if (p.opacity !== undefined) o.opacity = num(p.opacity, 1);
  if (p.shadowColor !== undefined) o.shadowColor = colour(p.shadowColor);
  if (p.shadowOffset !== undefined) {
    const s = num(p.shadowOffset, 0);
    o.shadowOffsetX = s; o.shadowOffsetY = -s; o.shadowBlur = o.shadowBlur ?? 4;
    o.shadowEnabled = true;
  }
  if (p.scale !== undefined) { const s = num(p.scale, 1); o.scaleX = s; o.scaleY = s; }
  return o;
}

/** props → a Konva node (or null when the shape cannot be placed). */
function build(p, onImage) {
  const type = String(p.type || '').toLowerCase();
  const at = pt(p, ['point', 'position', 'center']);
  const from = pt(p, ['from']), to = pt(p, ['to']);
  const size = pt(p, ['size']);
  const c = common(p);

  switch (type) {
    case 'rectangle': {
      if (from && to) {
        return new Konva.Rect({
          x: Math.min(from[0], to[0]), y: Math.min(from[1], to[1]),
          width: Math.abs(to[0] - from[0]), height: Math.abs(to[1] - from[1]),
          cornerRadius: num(p.radius, 0), ...c,
        });
      }
      if (at && size) {
        return new Konva.Rect({
          x: at[0], y: at[1], width: size[0], height: size[1],
          cornerRadius: num(p.radius, 0), ...c,
        });
      }
      return null;
    }
    case 'circle':
      return at ? new Konva.Circle({ x: at[0], y: at[1], radius: num(p.radius, 10), ...c }) : null;
    case 'ellipse':
      return at ? new Konva.Ellipse({
        x: at[0], y: at[1],
        radiusX: size ? size[0] / 2 : num(p.radius, 10),
        radiusY: size ? size[1] / 2 : num(p.radius, 10), ...c,
      }) : null;
    case 'arc':
      return at ? new Konva.Arc({
        x: at[0], y: at[1],
        innerRadius: num(p.radius1, num(p.radius, 10) * 0.6),
        outerRadius: num(p.radius2, num(p.radius, 10)),
        angle: num(p.angle, 180), rotation: num(p.rotation, 0), ...c,
      }) : null;
    case 'star':
      return at ? new Konva.Star({
        x: at[0], y: at[1], numPoints: num(p.points, 5),
        innerRadius: num(p.radius1, 10), outerRadius: num(p.radius2, 20), ...c,
      }) : null;
    case 'regularpolygon':
      return at ? new Konva.RegularPolygon({
        x: at[0], y: at[1], sides: num(p.sides, num(p.points, 6)),
        radius: num(p.radius, 20), ...c,
      }) : null;
    case 'line':
      return (from && to) ? new Konva.Line({
        points: [from[0], from[1], to[0], to[1]],
        stroke: c.stroke || 'currentColor', strokeWidth: c.strokeWidth || 2, ...c,
      }) : null;
    case 'path': {
      if (Array.isArray(p.segments)) {
        const pts = p.segments.flatMap((s) => (Array.isArray(s) ? [num(s[0], 0), num(s[1], 0)] : []));
        return new Konva.Line({ points: pts, tension: num(p.tension, 0), ...c, strokeWidth: c.strokeWidth || 2 });
      }
      return p.data ? new Konva.Path({ data: String(p.data), ...c }) : null;
    }
    case 'arrow':
      return (from && to) ? new Konva.Arrow({
        points: [from[0], from[1], to[0], to[1]],
        pointerLength: 9, pointerWidth: 8,
        pointerAtBeginning: p.biDirectional !== undefined,
        stroke: c.stroke || '#4aa3ff', fill: c.fill || c.stroke || '#4aa3ff',
        strokeWidth: c.strokeWidth || 2, ...c,
      }) : null;
    case 'text':
    case 'pointtext': {
      if (!at) return null;
      const t = new Konva.Text({
        x: at[0], y: at[1], text: String(p.content ?? p.label ?? ''),
        fontSize: num(p.fontSize, 13), fill: c.fill || c.stroke || '#ddd',
      });
      t.scaleY(-1);                              // counter-flip: y grows up
      return t;
    }
    case 'raster':
    case 'image': {
      const g = new Konva.Group({ x: at ? at[0] : 0, y: at ? at[1] : 0 });
      const s = num(p.scale, 1), w = 120 * s, h = 120 * s;
      //  A marker underneath, because the corpus has dead image links and an
      //  object that does not load should still be visible as a position.
      g.add(new Konva.Circle({ radius: 6, fill: '#4aa3ff', opacity: 0.35 }));
      const src = resolveIcon(p);
      if (src) {
        const img = new Image();
        img.crossOrigin = 'anonymous';
        img.onload = () => {
          const k = new Konva.Image({ image: img, x: -w / 2, y: -h / 2, width: w, height: h });
          k.scaleY(-1); k.y(h / 2);
          g.add(k); onImage();
        };
        img.src = src;
      }
      return g;
    }
    default:
      return null;
  }
}

/* `label:` is the old renderer's convenience — "rendered in an arbitrary
 * position; for precise positioning use a pointText object instead"
 * (2dWord.md). Arbitrary is not the same as unhelpful, though: a label
 * belongs *on* a big shape (a room) and *above* a small one (a person), and
 * it must never leave the shape's own extent by much, or it drags the scene's
 * bounding box out and everything else shrinks to fit a word.
 */
function labelFor(p, node) {
  if (p.label === undefined || p.label === null || p.label === '') return null;
  /*  In the *group's* coordinates, not the node's own.
   *
   *  `skipTransform` drops the node's own x/y, which is where a rectangle or a
   *  circle keeps its position — so every label in a scene of boxes was placed
   *  relative to (0, 0) and the whole cast ended up stacked in one illegible
   *  pile at the bottom-left corner of the world. It only looked right for
   *  `raster`, whose node is a group already sitting at the right place. */
  const box = node.getClientRect({ relativeTo: node.getParent() });
  const t = new Konva.Text({
    text: String(p.label), fontSize: num(p.fontSize, 12),
    fill: '#e8e8e8', stroke: '#15181e', strokeWidth: 3, fillAfterStrokeEnabled: true,
    listening: false,
  });
  t.scaleY(-1);
  t.x(box.x + box.width / 2 - t.width() / 2);
  const inside = box.height >= t.fontSize() * 2.5;
  //  y-up world: the shape's top edge is box.y + box.height.
  t.y(inside ? box.y + box.height - 4 : box.y + box.height + t.fontSize() + 2);
  return t;
}

export function renderScene2d(pane, data, cycle) {
  pane.dataset.lpsCycle = String(cycle);
  const objects = [...(data.timeless || []).map((p) => ({ props: p, key: null, live: false })),
    ...(data.items || []).map((i) => ({
      props: i.props, key: i.subject, live: true,
      kind: i.kind === 'event' ? 'event' : 'fluent',
    }))];

  if (!objects.length) {
    //  The offer belongs *here*, not only in a collapsed panel's header: this
    //  is where the reader is when they find out the program has no picture.
    emptyWithOffer(pane, 'display/2', 'Animate in 2D', 'animate-2d');
    stage = null; prev = new Map();
    return null;
  }

  if (lastPane !== pane || !stage || !pane.contains(stage.container())) {
    /*  A host of its own, pinned to the pane. Mounting the stage straight into
     *  the pane made the canvas part of the pane's own scroll height, and with
     *  `overflow: auto` that is a feedback loop: the canvas is sized from the
     *  pane, the pane grows to fit the canvas, the next resize makes it taller
     *  again. It reached 2500 px and the scene was somewhere off the bottom. */
    pane.replaceChildren();
    const host = document.createElement('div');
    host.className = 'scene-host';
    pane.appendChild(host);
    stage = new Konva.Stage({ container: host, width: pane.clientWidth || 600, height: pane.clientHeight || 420 });
    layer = new Konva.Layer();
    content = new Konva.Group();
    layer.add(content);
    stage.add(layer);
    prev = new Map();
    lastPane = pane;
    installControls(pane);
    installWhy(pane);
    new ResizeObserver(() => {
      if (!stage || !pane.isConnected) return;
      const w = host.clientWidth, h = host.clientHeight;
      if (!w || !h) return;
      stage.size({ width: w, height: h });
      fit();
    }).observe(host);
  }

  const next = new Map();
  //  An image that arrives late changes the extent, so re-fit when it does.
  const redraw = () => { fit(); layer.batchDraw(); };
  content.destroyChildren();
  for (const o of objects) {
    const node = build(o.props, redraw);
    if (!node) continue;
    node.opacity(node.opacity() ?? 1);
    const g = new Konva.Group();
    g.add(node);
    const lab = labelFor(o.props, node);
    if (lab) g.add(lab);
    //  Every drawn object knows which fluent or event it stands for, so a
    //  right-click on the picture can ask about the term. Konva draws to one
    //  canvas, so the delegated listener in why.js cannot see shapes — the
    //  stage does its own hit test and opens the same modal.
    if (o.key) g.setAttr('lpsSubject', { term: o.key, kind: o.kind || 'fluent' });
    content.add(g);
    if (o.key) {
      const before = prev.get(o.key);
      const target = { x: g.x(), y: g.y() };
      if (before) {
        //  The object existed last cycle: slide from where it was.
        g.position({ x: before.x, y: before.y });
        new Konva.Tween({ node: g, x: target.x, y: target.y, duration: DUR, easing: Konva.Easings.EaseInOut }).play();
      } else {
        g.opacity(0);
        new Konva.Tween({ node: g, opacity: 1, duration: DUR }).play();
      }
      next.set(o.key, target);
    }
  }
  prev = next;
  fit();
  //  The legend: one row per fluent drawn, in its own colour. Built from what
  //  was actually placed, so it cannot drift from the picture.
  sceneToolbar(pane, {
    canvas: () => pane.querySelector('canvas'),
    cycle,
    onCompare: () => window.dispatchEvent(new CustomEvent('lps-compare-cycles', { detail: { kind: '2d', cycle } })),
  });
  sceneLegend(pane, [...new Map(objects.filter((o) => o.key)
    .map((o) => [String(o.key).replace(/\(.*$/, ''),
      { colour: colourOf(o.props), label: String(o.key).replace(/\(.*$/, '') }])).values()]);
  return { stage, cycle };
}

//  What colour this object was drawn in, for the legend.
function colourOf(p) {
  const v = p?.fillColor ?? p?.color ?? p?.strokeColor;
  return v === undefined || v === null ? '#888' : colour(v, '#888');
}

/* Bottom-left origin, and everything scaled to fit.
 *
 * With the content layer scaled (k, -k), a world point (x, y) lands at
 * (pos.x + k·x, pos.y − k·y). Pinning the world's top-left corner
 * (box.x, box.y+h) to the stage's top-left padding gives the position
 * directly — which is worth writing down, because getting the sign wrong here
 * puts the whole scene off-screen and looks exactly like "nothing rendered". */
function fit() {
  if (!stage || !content) return;
  const box = content.getClientRect({ relativeTo: content });
  const w = Math.max(1, box.width), h = Math.max(1, box.height);
  const sw = stage.width(), sh = stage.height();
  const pad = 24;
  const s = Math.min((sw - pad * 2) / w, (sh - pad * 2) / h);
  const k = isFinite(s) && s > 0 ? Math.min(s, 4) : 1;
  content.scale({ x: k, y: -k });
  const offX = (sw - w * k) / 2, offY = (sh - h * k) / 2;
  content.position({ x: offX - box.x * k, y: offY + (box.y + h) * k });
  /*  Publish the mapping, so a click can be reported in the program's own
   *  units rather than in pixels. A world point (wx, wy) lands at
   *  (px + k·wx, py − k·wy), so the inverse is what a viewer needs. */
  window.LPS_SCENE_TRANSFORM = { k, px: content.x(), py: content.y() };
  stage.batchDraw();
}

/*  The 2D scene is one canvas, so there is nothing for a DOM listener to hit.
 *  Konva's own hit test finds the shape; walking up to the group finds the
 *  subject term the renderer recorded on it. */
function installWhy(pane) {
  pane.addEventListener('contextmenu', (e) => {
    const subj = subjectAt(e);
    if (!subj) return;
    e.preventDefault();
    window.dispatchEvent(new CustomEvent('lps-why', { detail: subj }));
  });
  //  Left-click: "when does this move next?" — answered by the IDE, which is
  //  the party that knows about cycles.
  pane.addEventListener('click', (e) => {
    if (e.button !== 0 || e.target.closest('.scene-tools, .vp-controls')) return;
    const subj = subjectAt(e);
    if (subj) window.dispatchEvent(new CustomEvent('lps-pick', { detail: subj }));
  });
}

/*  What the pointer is over, from the *event* rather than from
 *  `stage.getPointerPosition()`. Konva only knows where the pointer is while
 *  it is dispatching one of its own events; asked from a DOM listener it
 *  answers with wherever it last was, or with nothing at all — which is why
 *  hover reported no object however carefully you aimed. */
function subjectAt(e) {
  if (!stage) return null;
  const box = stage.container().getBoundingClientRect();
  const shape = stage.getIntersection({ x: e.clientX - box.left, y: e.clientY - box.top });
  let g = shape;
  while (g && !g.getAttr('lpsSubject')) g = g.getParent();
  return (g && g.getAttr('lpsSubject')) || null;
}

function installControls(pane) {
  pane.classList.add('vp-host');
  const box = document.createElement('div');
  box.className = 'vp-controls';
  const mk = (t, title, fn) => {
    const b = document.createElement('button');
    b.textContent = t; b.title = title;
    b.addEventListener('click', (e) => { e.stopPropagation(); fn(); });
    box.appendChild(b);
  };
  const zoom = (f) => {
    const c = { x: stage.width() / 2, y: stage.height() / 2 };
    const s = content.scaleX() * f;
    content.scale({ x: s, y: -Math.abs(s) });
    content.position({ x: c.x - (c.x - content.x()) * f, y: c.y - (c.y - content.y()) * f });
    stage.batchDraw();
  };
  mk('+', 'Zoom in', () => zoom(1.25));
  mk('−', 'Zoom out', () => zoom(0.8));
  mk('⤢', 'Fit', fit);
  pane.appendChild(box);

  //  Wheel and drag, on the stage itself.
  pane.addEventListener('wheel', (e) => {
    if (!stage) return;
    e.preventDefault();
    zoom(Math.exp(-e.deltaY * 0.0012));
  }, { passive: false });
  /*  Panning, and *only* on the left button.
   *
   *  A right-click also fires pointerdown, which used to start a drag; the
   *  context menu then opened a modal, the matching pointerup went to the
   *  modal instead of here, and the scene followed the mouse for ever after.
   *  Three fixes, all of them the same fix: start on button 0 only, capture
   *  the pointer so the release always comes back, and let go on anything
   *  that ends a gesture. */
  let drag = null;
  const endDrag = () => { drag = null; pane.classList.remove('vp-grabbing'); };
  pane.addEventListener('pointerdown', (e) => {
    /*  Not on a control. The pane captures the pointer for the drag, and a
     *  captured pointer delivers its `click` to the capturing element rather
     *  than to the button under it — so a toolbar button pressed here would
     *  simply never fire. */
    if (e.button !== 0 || e.target.closest('.vp-controls, .scene-tools, .scene-legend')) return;
    drag = { x: e.clientX, y: e.clientY, cx: content.x(), cy: content.y(), id: e.pointerId };
    try { pane.setPointerCapture(e.pointerId); } catch { /* not capturable */ }
    pane.classList.add('vp-grabbing');
  });
  pane.addEventListener('pointermove', (e) => {
    if (!drag) { hover(e); return; }
    content.position({ x: drag.cx + (e.clientX - drag.x), y: drag.cy + (e.clientY - drag.y) });
    stage.batchDraw();
  });
  pane.addEventListener('pointerup', (e) => {
    if (drag) { try { pane.releasePointerCapture(drag.id); } catch { /* gone */ } }
    endDrag();
  });
  pane.addEventListener('pointercancel', endDrag);
  pane.addEventListener('pointerleave', endDrag);
  pane.addEventListener('contextmenu', endDrag);
  pane.addEventListener('dblclick', fit);

  /*  What is under the pointer, as a tooltip. Konva draws to one canvas, so
   *  there is nothing to hang a `title` on; the stage's own hit test finds the
   *  shape and the group carries the term it stands for.
   *
   *  A floating label rather than `pane.title`: the native tooltip waits a
   *  second, is unstyled, and disappears the moment the pointer moves — which
   *  is most of the time, in a pane you are moving around in. */
  function hover(e) {
    const subj = subjectAt(e);
    showTip(pane, subj ? `${subj.term}   ·  cycle ${pane.dataset.lpsCycle || '?'}` : null, e);
    pane.style.cursor = subj ? 'context-menu' : '';
  }
  pane.addEventListener('pointerleave', () => showTip(pane, null, {}));
}



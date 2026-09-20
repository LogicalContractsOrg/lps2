/* scene3d.js — the 3D pane, on three.js (M15c).
 *
 * Driven by `display3d/2`, a *new* declaration rather than a reinterpretation
 * of `display/2`. Two-dimensional props do not carry into three dimensions
 * without lying about what the author meant — `from`/`to` says "a rectangle
 * between these corners", which in 3D could be a box, a plane or a wall — and
 * a program may reasonably want both mappings at once, showing different
 * things.
 *
 * The declaration, documented in docs/user/reference/lps.md:
 *
 *   display3d(Subject, [ type:box, position:[X,Y,Z], size:[W,H,D],
 *                        color:green, opacity:0.8, rotation:[Rx,Ry,Rz],
 *                        label:'text' ]).
 *   display3d(timeless, [ [type:ground, size:[40,40], color:'#333'],
 *                         [type:camera, position:[12,10,12], lookAt:[0,0,0]],
 *                         [type:light, position:[8,14,6]] ]).
 *
 * Types: box, sphere, cylinder, cone, plane, ground, line, arrow, text,
 * camera, light. Coordinates are right-handed with **y up**, which is three's
 * own convention and, unlike the 2D pane, not something the corpus has an
 * opinion about.
 *
 * Motion between cycles is the same idea as the 2D pane: objects are keyed by
 * their subject term, and one that persists interpolates from where it was.
 */
import { showTip, emptyWithOffer, sceneLegend, sceneToolbar } from './shared.js';
import { sayTerm, sayPredicate } from '../le-words.js';
import * as THREE from 'three';
import { patternUrl, hasPattern } from '../patterns.js';
import { buildModel, hasModel } from '../models3d.js';

let ctx = null;

const num = (v, d) => (typeof v === 'number' ? v : (typeof v === 'string' && v !== '' && !isNaN(+v) ? +v : d));
const vec = (p, k, d) => (Array.isArray(p[k]) ? p[k].map((n) => num(n, 0)) : d);
/*  Always a THREE.Color, never sometimes a string.
 *
 *  The first version returned the *default* unconverted, so `type:arrow`
 *  without an explicit colour reached `colour(p.color, '#ffd479').getHex()` and
 *  threw `colour(...).getHex is not a function` — which the pane then displayed
 *  as its content, and which is where a JavaScript fragment in the middle of a
 *  3D scene comes from. Every caller now gets the same type. */
const colour = (v, d) => {
  const dflt = () => { try { return new THREE.Color(d); } catch { return new THREE.Color('#7aa2f7'); } };
  if (v === undefined || v === null || v === '') return dflt();
  if (Array.isArray(v)) return new THREE.Color(num(v[0], 0), num(v[1], 0), num(v[2], 0));
  try { return new THREE.Color(String(v)); } catch { return dflt(); }
};

function material(p) {
  const m = new THREE.MeshStandardMaterial({
    color: colour(p.color ?? p.fillColor, '#7aa2f7'),
    roughness: num(p.roughness, 0.65),
    metalness: num(p.metalness, 0.05),
    transparent: p.opacity !== undefined && num(p.opacity, 1) < 1,
    opacity: num(p.opacity, 1),
  });
  patternTexture(p, m);
  return m;
}

/*  `pattern:` in three dimensions is the same tile as in two (ui/patterns),
 *  loaded as the material's map — so a 2D scene and its 3D twin say the same
 *  thing about a surface. The tile is drawn in ink on transparent and tinted
 *  by the material's own colour, which is why a patterned box is still the
 *  colour it was given. */
const textures = new Map();
function patternTexture(p, m) {
  const name = String(p.pattern ?? '');
  if (!name || !hasPattern(name)) return;
  const rep = Math.max(1, Math.round(num(p.patternScale, 2)));
  const key = `${name}|${rep}`;
  let tex = textures.get(key);
  if (!tex) {
    const url = patternUrl(name, 'rgba(255,255,255,0.85)', 'rgba(255,255,255,0.15)');
    if (!url) return;
    tex = new THREE.TextureLoader().load(url);
    tex.wrapS = THREE.RepeatWrapping; tex.wrapT = THREE.RepeatWrapping;
    tex.repeat.set(rep, rep);
    textures.set(key, tex);
  }
  m.map = tex;
  m.needsUpdate = true;
}

function build(p) {
  const type = String(p.type || 'box').toLowerCase();
  const size = vec(p, 'size', null);
  let mesh = null;
  /*  A named object from the catalogue (ui/models3d): `[type:model,
   *  model:tree]`, or just `model:tree`. It is a group of primitives in the
   *  object's own colour — what the icons are to a 2D scene. */
  if (type === 'model' || (p.model && hasModel(p.model))) {
    const g = buildModel(p.model ?? p.icon, p);
    /*  A model STANDS on y = 0 of its own group, while a box is centred on its
     *  position. So when the object also carries a `size` — which is what a
     *  generated layer clause gives, one clause serving both — lower the model
     *  by half of it, and "position" means the same thing either way: the
     *  centre of the space this thing occupies. Without this a scene of models
     *  floats half a cell above its floor. */
    if (g) {
      const h = size?.[1];
      if (typeof h === 'number') g.position.y -= h / 2;
      return g;
    }
  }
  switch (type) {
    case 'box':
      mesh = new THREE.Mesh(new THREE.BoxGeometry(
        size?.[0] ?? num(p.width, 1), size?.[1] ?? num(p.height, 1), size?.[2] ?? num(p.depth, 1)), material(p));
      break;
    case 'sphere':
      mesh = new THREE.Mesh(new THREE.SphereGeometry(num(p.radius, size?.[0] ?? 0.5), 24, 18), material(p));
      break;
    case 'cylinder':
      mesh = new THREE.Mesh(new THREE.CylinderGeometry(
        num(p.radius, 0.5), num(p.radius2, num(p.radius, 0.5)), num(p.height, size?.[1] ?? 1), 24), material(p));
      break;
    case 'cone':
      mesh = new THREE.Mesh(new THREE.ConeGeometry(num(p.radius, 0.5), num(p.height, 1), 24), material(p));
      break;
    case 'plane':
    case 'ground': {
      const g = new THREE.PlaneGeometry(size?.[0] ?? 20, size?.[1] ?? 20);
      const m = new THREE.MeshStandardMaterial({
        color: colour(p.color, type === 'ground' ? '#2a2f3a' : '#445'),
        side: THREE.DoubleSide, roughness: 0.95,
      });
      mesh = new THREE.Mesh(g, m);
      if (type === 'ground') { mesh.rotation.x = -Math.PI / 2; mesh.userData.isGround = true; }
      break;
    }
    case 'line':
    case 'arrow': {
      const a = vec(p, 'from', [0, 0, 0]), b = vec(p, 'to', [1, 0, 0]);
      const va = new THREE.Vector3(...a), vb = new THREE.Vector3(...b);
      if (type === 'arrow') {
        const dir = vb.clone().sub(va);
        const len = dir.length() || 1;
        mesh = new THREE.ArrowHelper(dir.normalize(), va, len, colour(p.color, '#ffd479').getHex(),
          Math.min(0.3 * len, 0.6), Math.min(0.2 * len, 0.4));
        return mesh;                                   // already positioned
      }
      const g = new THREE.BufferGeometry().setFromPoints([va, vb]);
      mesh = new THREE.Line(g, new THREE.LineBasicMaterial({ color: colour(p.color, '#8fa') }));
      return mesh;
    }
    case 'text':
      return textSprite(p);
    default:
      return null;
  }
  return mesh;
}

/* A label the viewer can actually read.
 *
 * The first version painted `#e8e8e8` on a transparent canvas. On the light
 * theme that is white text on near-white — a label that is technically present
 * and practically invisible, which is the complaint that produced this
 * function. Three things fix it, and none of them is "pick a better colour":
 *
 *   1. **Follow the theme.** The renderer is `alpha: true`, so the background
 *      is the app's, and the app already publishes which one it is in.
 *   2. **Outline the glyphs.** A label also crosses *geometry*, whose colour is
 *      the program's business and not knowable here. A stroke in the background
 *      ink survives both cases.
 *   3. **Let the program override**, because `color:` on a display3d text is
 *      the author saying they know better — and then still outline it, so even
 *      a badly chosen colour stays readable.
 */
let INK = { fg: '#101317', bg: '#f2f4f8' };

export function setSceneInk() {
  //  The app already knows which theme it is in — `body[data-theme]` is what
  //  every colour in style.css keys off — so ask that rather than trying to
  //  read a computed background through a transparent WebGL canvas.
  const light = document.body.dataset.theme === 'light';
  INK = { fg: light ? '#101317' : '#eef1f6', bg: light ? '#f7f8fa' : '#0f1216' };
}

function textSprite(p) {
  //  A sprite rather than real geometry: no font loading, always legible, and
  //  it faces the camera, which is what a label wants to do.
  const text = String(p.label ?? p.content ?? '');
  const font = 'bold 48px system-ui, sans-serif';
  const cvs = document.createElement('canvas');
  const measure = cvs.getContext('2d');
  measure.font = font;
  cvs.width = Math.max(64, Math.ceil(measure.measureText(text).width) + 32);
  cvs.height = 72;
  const c2 = cvs.getContext('2d');
  c2.font = font;
  c2.textBaseline = 'middle';
  c2.lineJoin = 'round';
  c2.lineWidth = 8;
  c2.strokeStyle = INK.bg;
  c2.strokeText(text, 16, 38);
  c2.fillStyle = p.color !== undefined && p.color !== null ? String(p.color) : INK.fg;
  c2.fillText(text, 16, 38);
  const tex = new THREE.CanvasTexture(cvs);
  tex.anisotropy = 4;
  const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true, depthTest: false }));
  const s = num(p.scale, 1);
  sp.scale.set((cvs.width / 72) * s, (cvs.height / 72) * s, 1);
  sp.renderOrder = 10;
  return sp;
}

function place(obj, p) {
  const at = vec(p, 'position', vec(p, 'point', [0, 0, 0]));
  obj.position.set(at[0] ?? 0, at[1] ?? 0, at[2] ?? 0);
  const rot = vec(p, 'rotation', null);
  if (rot) obj.rotation.set(
    THREE.MathUtils.degToRad(rot[0] || 0),
    THREE.MathUtils.degToRad(rot[1] || 0),
    THREE.MathUtils.degToRad(rot[2] || 0));
  return obj;
}

/*  One scene, rendered once into an image (AnimationPlan.md §7).
 *
 *  The strip wants a dozen small pictures of a run, and a dozen WebGL contexts
 *  is not a way to get them: browsers cap them at about sixteen and start
 *  dropping the oldest, so the first frames of a strip would go black while
 *  the last were still drawing. One renderer, reused, rendering each frame and
 *  handing back a data URL, has no such limit — and a frame of a strip is a
 *  still picture, which is all an <img> is.
 */
let snapCtx = null;
export function snapshot3d(data, width, height) {
  const w = Math.max(64, Math.round(width)), h = Math.max(48, Math.round(height));
  if (!snapCtx) {
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true,
                                               preserveDrawingBuffer: true });
    renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
    snapCtx = { renderer, camera: new THREE.PerspectiveCamera(50, w / h, 0.1, 500) };
  }
  const { renderer } = snapCtx;
  renderer.setSize(w, h);
  const camera = snapCtx.camera;
  camera.aspect = w / Math.max(1, h);
  const scene = new THREE.Scene();
  scene.add(new THREE.AmbientLight(0xffffff, 0.55));
  camera.position.set(14, 12, 16);
  const target = new THREE.Vector3(0, 0, 0);
  let sawLight = false;
  //  What the picture is OF, for the framing below: everything but the ground,
  //  which is as wide as the world and would frame nothing.
  const content = new THREE.Box3();
  const add = (p) => {
    const type = String(p.type || '').toLowerCase();
    if (type === 'camera') {
      const at = vec(p, 'position', [14, 12, 16]);
      const look = vec(p, 'lookAt', [0, 0, 0]);
      camera.position.set(...at); target.set(...look);
      return;
    }
    if (type === 'light') {
      const at = vec(p, 'position', [10, 16, 8]);
      const l = new THREE.DirectionalLight(colour(p.color, '#ffffff'), num(p.intensity, 1.1));
      l.position.set(...at); scene.add(l); sawLight = true;
      return;
    }
    const obj = build(p);
    if (!obj) return;
    place(obj, p);
    scene.add(obj);
    if (type !== 'ground') { try { content.expandByObject(obj); } catch { /* no geometry */ } }
    if (p.label && type !== 'text') {
      const lab = build({ type: 'text', label: p.label, scale: num(p.labelScale, 0.9) });
      const at = vec(p, 'position', [0, 0, 0]);
      const hh = vec(p, 'size', [1, 1, 1])[1] ?? num(p.radius, 0.5) * 2;
      lab.position.set(at[0], (at[1] ?? 0) + (hh >= 1.2 ? 0 : hh * 0.7 + 0.6), at[2]);
      scene.add(lab);
    }
  };
  for (const p of (data.timeless || [])) { try { add(p); } catch { /* one object */ } }
  for (const it of (data.items || [])) { try { add(it.props); } catch { /* one object */ } }
  if (!sawLight) {
    const l = new THREE.DirectionalLight(0xffffff, 1.1);
    l.position.set(10, 16, 8);
    scene.add(l);
  }
  /*  Frame the thumbnail on what is in it (the review's R9).
   *
   *  A frame is photographed with the scene's *declared* camera, which was
   *  chosen for a full pane: in a 220×150 card the subject came out a few
   *  pixels across. The declared camera still says where the photographer
   *  stands — the direction is the program's choice and the whole strip must
   *  agree on it — but how far back is this picture's business. */
  if (!content.isEmpty()) {
    const centre = content.getCenter(new THREE.Vector3());
    const dir = camera.position.clone().sub(target);
    if (dir.lengthSq() < 1e-6) dir.set(1, 0.9, 1.1);
    dir.normalize();
    //  The box, in the camera's own axes — not its bounding sphere. A row of
    //  five gauges is thirty units wide and two high, and a sphere around it
    //  is fifteen units of mostly nothing: framed by the sphere it came out a
    //  sixth of the size it could have been.
    let right = new THREE.Vector3().crossVectors(new THREE.Vector3(0, 1, 0), dir);
    if (right.lengthSq() < 1e-6) right = new THREE.Vector3(1, 0, 0);
    right.normalize();
    const up = new THREE.Vector3().crossVectors(dir, right).normalize();
    const vfov = (camera.fov * Math.PI) / 180;
    const tanV = Math.tan(vfov / 2), tanH = tanV * camera.aspect;
    const lo = content.min, hi = content.max;
    let dist = 0.6;
    for (const cx of [lo.x, hi.x]) for (const cy of [lo.y, hi.y]) for (const cz of [lo.z, hi.z]) {
      const v = new THREE.Vector3(cx, cy, cz).sub(centre);
      const depth = v.dot(dir);
      dist = Math.max(dist,
        Math.abs(v.dot(right)) / tanH + depth,
        Math.abs(v.dot(up)) / tanV + depth);
    }
    dist *= 1.06;
    camera.position.copy(centre).add(dir.multiplyScalar(dist));
    camera.near = Math.max(0.05, dist / 100);
    camera.far = dist * 6 + 40;
    target.copy(centre);
  }
  camera.lookAt(target);
  camera.updateProjectionMatrix();
  renderer.render(scene, camera);
  const url = renderer.domElement.toDataURL('image/png');
  scene.clear();
  return url;
}

export function renderScene3d(pane, data, cycle) {
  pane.dataset.lpsCycle = String(cycle);
  const timeless = data.timeless || [];
  const items = data.items || [];
  if (!timeless.length && !items.length) {
    emptyWithOffer(pane, 'display3d/2', 'Animate in 3D', 'animate-3d');
    if (ctx) { ctx.stop = true; ctx = null; }
    return null;
  }

  if (!ctx || ctx.pane !== pane || !pane.contains(ctx.renderer.domElement)) {
    if (ctx) ctx.stop = true;
    //  Same fixed host as the 2D pane, and for the same reason: a canvas
    //  inside a scrollable pane whose size is read back from that pane grows
    //  without bound.
    pane.replaceChildren();
    const host = document.createElement('div');
    host.className = 'scene-host';
    pane.appendChild(host);
    //  preserveDrawingBuffer so the canvas can be read back: without it
    //  `toDataURL` returns a blank image, because the browser is free to
    //  discard the buffer the moment it has been composited.
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true,
                                               preserveDrawingBuffer: true });
    renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
    renderer.setSize(host.clientWidth || 600, host.clientHeight || 420);
    host.appendChild(renderer.domElement);
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(50, (pane.clientWidth || 600) / (pane.clientHeight || 420), 0.1, 500);
    camera.position.set(14, 12, 16);
    camera.lookAt(0, 0, 0);
    ctx = {
      pane, host, renderer, scene, camera, objects: new Map(), stop: false,
      target: new THREE.Vector3(0, 0, 0),
      //  `cameraSpec` is the last display3d(timeless, [type:camera…]) we
      //  obeyed, and `userMoved` records that somebody has since dragged or
      //  zoomed. Between them they are why scrubbing to the next cycle no
      //  longer throws the view away: the declaration is a *starting* camera,
      //  not a per-frame instruction.
      cameraSpec: null, userMoved: false,
    };
    orbit(pane, ctx);
    whyPicker(pane, ctx);
    new ResizeObserver(() => {
      if (!ctx || !pane.isConnected) return;
      const w = host.clientWidth, h = host.clientHeight;
      if (!w || !h) return;
      ctx.renderer.setSize(w, h);
      ctx.camera.aspect = w / Math.max(1, h);
      ctx.camera.updateProjectionMatrix();
    }).observe(host);
    controls(pane, ctx);
    const loop = () => {
      if (!ctx || ctx.stop) return;
      tween(ctx);
      followTarget(ctx);
      ctx.renderer.render(ctx.scene, ctx.camera);
      requestAnimationFrame(loop);
    };
    loop();
  }

  setSceneInk();
  fitCanvas(ctx);
  const { scene } = ctx;
  scene.clear();
  scene.add(new THREE.AmbientLight(0xffffff, 0.55));

  let sawLight = false;
  //  `key` is the identity a moving object keeps between cycles (so it
  //  tweens); `meta` is what a right-click should ask about — for a composite
  //  event that is the act itself, at the cycle it ended, not the engine's
  //  `happens(Act, Start, End)` record of it.
  const addProps = (p, key, meta) => {
    const type = String(p.type || '').toLowerCase();
    if (type === 'camera') {
      const at = vec(p, 'position', [14, 12, 16]);
      const look = vec(p, 'lookAt', [0, 0, 0]);
      //  Obey the declaration when it is new, and not otherwise. Re-applying it
      //  every cycle is what reset the zoom the moment the slider moved.
      const spec = JSON.stringify([at, look]);
      if (spec !== ctx.cameraSpec && !ctx.userMoved) {
        ctx.camera.position.set(...at);
        ctx.target.set(...look);
        ctx.camera.lookAt(ctx.target);
      }
      ctx.cameraSpec = spec;
      return;
    }
    if (type === 'light') {
      const at = vec(p, 'position', [10, 16, 8]);
      const l = new THREE.DirectionalLight(colour(p.color, '#ffffff'), num(p.intensity, 1.1));
      l.position.set(...at);
      scene.add(l);
      sawLight = true;
      return;
    }
    const obj = build(p);
    if (!obj) return;
    place(obj, p);
    if (key) {
      obj.userData.subject = meta?.ask || key;
      obj.userData.kind = meta?.kind || 'fluent';
      obj.userData.at = meta?.at;
      const before = ctx.objects.get(key);
      if (before) {
        obj.userData.from = before.clone();
        obj.userData.to = obj.position.clone();
        obj.userData.t = 0;
        obj.position.copy(before);
      }
      ctx.objects.set(key, obj.position.clone());
      obj.userData.key = key;
    }
    scene.add(obj);
    /*  A label belongs *on* a big object and *above* a small one — the same
     *  rule the 2D renderer follows, and for the same reason. Floating every
     *  label a fixed distance above its object is fine for things standing
     *  apart on a floor and wrong for anything stacked: in a tower of 1.6-unit
     *  blocks at a 1.8 pitch, `y + 1.72` puts each block's name on the block
     *  above it, so the whole column reads as if it were labelled one out and
     *  the bottom block looks unlabelled. The sprite has `depthTest: false`,
     *  so a label at the object's own centre draws over it rather than inside. */
    if (p.label && String(p.type).toLowerCase() !== 'text') {
      const lab = build({ type: 'text', label: p.label, scale: num(p.labelScale, 0.9) });
      const at = vec(p, 'position', [0, 0, 0]);
      const h = vec(p, 'size', [1, 1, 1])[1] ?? num(p.radius, 0.5) * 2;
      const inside = h >= 1.2;
      lab.position.set(at[0], (at[1] ?? 0) + (inside ? 0 : h * 0.7 + 0.6), at[2]);
      scene.add(lab);
    }
  };

  /*  One bad object should cost one object, not the scene. Before this, a prop
   *  the renderer could not make sense of threw out of renderScene3d, and the
   *  pane's error path replaced the whole canvas with the exception's text. */
  const bad = [];
  const safely = (p, key, meta) => {
    try { addProps(p, key, meta); }
    catch (e) { bad.push(`${key || 'backdrop'}: ${e.message}`); }
  };
  for (const p of timeless) safely(p, null, null);
  for (const it of items) {
    safely(it.props, it.subject, {
      ask: it.ask, at: it.at,
      kind: it.kind === 'fluent' ? 'fluent' : 'event',
    });
  }
  if (bad.length) console.warn('display3d: ' + bad.join(' | '));
  sceneToolbar(pane, {
    canvas: () => pane.querySelector('canvas'),
    cycle,
    onCompare: () => window.dispatchEvent(new CustomEvent('lps-compare-cycles', { detail: { kind: '3d', cycle } })),
  });
  //  One row per fluent drawn, in the colour it was drawn in.
  sceneLegend(pane, [...new Map(items.filter((i) => i.subject).map((i) => {
    const name = String(i.ask || i.subject).replace(/\(.*$/, '');
    const v = i.props?.color ?? i.props?.fillColor;
    return [name, { colour: v == null ? '#888' : '#' + colour(v, '#888').getHexString(), label: sayPredicate(name) }];
  })).values()]);
  if (!sawLight) {
    const l = new THREE.DirectionalLight(0xffffff, 1.1);
    l.position.set(10, 16, 8);
    scene.add(l);
  }
  return { cycle };
}


/*  The ResizeObserver misses the case that matters most: the pane is
 *  `display:none` until its tab is chosen, so the first setSize happens against
 *  a zero-sized host and falls back to 600×420. The canvas then sits in the
 *  corner of a larger pane — invisible on the dark theme, an obvious white band
 *  on the light one. Checking on every render costs two property reads. */
function fitCanvas(c) {
  const w = c.host.clientWidth, h = c.host.clientHeight;
  if (!w || !h) return;
  const size = c.renderer.getSize(new THREE.Vector2());
  if (Math.abs(size.x - w) < 1 && Math.abs(size.y - h) < 1) return;
  c.renderer.setSize(w, h);
  c.camera.aspect = w / Math.max(1, h);
  c.camera.updateProjectionMatrix();
}

export function fitView(c) {
  c.userMoved = false;
  const box = new THREE.Box3();
  let any = false;
  c.scene.traverse((o) => {
    if (!o.isMesh && !o.isLine) return;
    //  Two things are deliberately left out. The **ground plane** is scenery:
    //  including it makes every scene a speck in the middle of a field. And
    //  **labels** are sprites whose world size is a scale factor rather than a
    //  measurement, so they pull the box around without adding anything the
    //  viewer needs to see — they follow their object regardless.
    if (o.userData?.isGround) return;
    box.expandByObject(o);
    any = true;
  });
  const spec = c.cameraSpec ? JSON.parse(c.cameraSpec) : [[14, 12, 16], [0, 0, 0]];
  if (!any || box.isEmpty()) {
    c.camera.position.set(...spec[0]);
    c.target.set(...spec[1]);
    c.camera.lookAt(c.target);
    return;
  }
  const centre = box.getCenter(new THREE.Vector3());
  const size = box.getSize(new THREE.Vector3());
  const radius = Math.max(0.5, size.length() / 2);
  //  Far enough that a sphere of that radius fits the *narrower* of the two
  //  fields of view, with a margin — which is the step the old reset skipped.
  const vFov = THREE.MathUtils.degToRad(c.camera.fov);
  const hFov = 2 * Math.atan(Math.tan(vFov / 2) * c.camera.aspect);
  //  1.6, not 1.0: the sphere bound is generous in the middle and tight at
  //  the corners, labels sit above their objects, and a reset that leaves the
  //  bottom row touching the edge is a reset somebody presses twice.
  const dist = 1.6 * radius / Math.sin(Math.min(vFov, hFov) / 2);
  const dir = new THREE.Vector3(...spec[0]).sub(new THREE.Vector3(...spec[1]));
  if (dir.lengthSq() < 1e-6) dir.set(1, 0.8, 1);
  dir.normalize();
  c.target.copy(centre);
  c.camera.position.copy(centre.clone().add(dir.multiplyScalar(dist)));
  c.camera.near = Math.max(0.05, dist / 500);
  c.camera.far = dist * 10;
  c.camera.updateProjectionMatrix();
  c.camera.lookAt(c.target);
}

function tween(ctx) {
  for (const obj of ctx.scene.children) {
    const u = obj.userData;
    if (!u || !u.from || u.t >= 1) continue;
    u.t = Math.min(1, u.t + 0.06);
    const e = u.t < 0.5 ? 2 * u.t * u.t : 1 - Math.pow(-2 * u.t + 2, 2) / 2;
    obj.position.lerpVectors(u.from, u.to, e);
  }
}

/*  Right-click a solid and ask about the fluent it stands for. A WebGL canvas
 *  has no DOM to delegate to, so the pick is a raycast — three's own, against
 *  the objects that carry a subject. */
function whyPicker(pane, c) {
  const ray = new THREE.Raycaster();

  /*  What is under the pointer, as a tooltip. Throttled to one raycast per
   *  animation frame, because pointermove fires far faster than that. */
  let pending = false;
  pane.addEventListener('pointermove', (e) => {
    if (pending || e.target.closest('.strip')) return;
    pending = true;
    requestAnimationFrame(() => {
      pending = false;
      const hit = pick(e.clientX, e.clientY);
      showTip(pane, hit ? `${sayTerm(hit)}   ·  cycle ${pane.dataset.lpsCycle || '?'}` : null, e);
      pane.style.cursor = hit ? 'context-menu' : '';
    });
  });

  function pick(clientX, clientY) {
    const r = c.host.getBoundingClientRect();
    const p = new THREE.Vector2(
      ((clientX - r.left) / r.width) * 2 - 1,
      -((clientY - r.top) / r.height) * 2 + 1);
    ray.setFromCamera(p, c.camera);
    for (const h of ray.intersectObjects(c.scene.children, true)) {
      let o = h.object;
      while (o && !o.userData?.subject) o = o.parent;
      if (o?.userData?.subject) return o.userData.subject;
    }
    return null;
  }

  /*  Where a screen point meets the ground plane, in world units. A click in
   *  three dimensions is a ray, and the only place to intersect it that a
   *  program can reason about is y = 0. */
  window.LPS_SCENE_PICK3D = (clientX, clientY) => {
    const r = c.host.getBoundingClientRect();
    const p = new THREE.Vector2(
      ((clientX - r.left) / r.width) * 2 - 1,
      -((clientY - r.top) / r.height) * 2 + 1);
    ray.setFromCamera(p, c.camera);
    const hit = new THREE.Vector3();
    const plane = new THREE.Plane(new THREE.Vector3(0, 1, 0), 0);
    return ray.ray.intersectPlane(plane, hit) ? [hit.x, hit.y, hit.z] : null;
  };
  //  What object is under the pointer, if any.
  const subjectAt = (e) => {
    const r = c.host.getBoundingClientRect();
    const p = new THREE.Vector2(
      ((e.clientX - r.left) / r.width) * 2 - 1,
      -((e.clientY - r.top) / r.height) * 2 + 1);
    ray.setFromCamera(p, c.camera);
    for (const h of ray.intersectObjects(c.scene.children, true)) {
      let o = h.object;
      while (o && !o.userData?.subject) o = o.parent;
      if (o?.userData?.subject) return o;
    }
    return null;
  };

  pane.addEventListener('contextmenu', (e) => {
    if (e.target.closest('.strip')) return;
    const o = subjectAt(e);
    if (!o) return;
    e.preventDefault();
    window.dispatchEvent(new CustomEvent('lps-why',
      { detail: { term: o.userData.subject, kind: o.userData.kind || 'fluent', at: o.userData.at } }));
  });

  /*  Left-click: the IDE goes to the next cycle in which this fluent changes.
   *  Shift-click: *follow* it — the camera keeps it centred as the cycles
   *  advance, which is the only way to watch one thing in a busy scene. */
  pane.addEventListener('click', (e) => {
    if (e.target.closest('.scene-tools, .vp-controls, .strip')) return;
    const o = subjectAt(e);
    if (!o) { if (e.shiftKey) c.follow = null; return; }
    if (e.shiftKey) {
      c.follow = c.follow === o.userData.subject ? null : o.userData.subject;
      c.userMoved = true;
      return;
    }
    window.dispatchEvent(new CustomEvent('lps-pick',
      { detail: { term: o.userData.subject, kind: o.userData.kind || 'fluent', at: o.userData.at } }));
  });
}

/*  Keep the followed object centred, if there is one. The camera keeps its
 *  direction and distance and only its aim point moves, so shift-clicking a
 *  thing does not also teleport the view. */
function followTarget(c) {
  if (!c.follow) return;
  let found = null;
  c.scene.traverse((o) => { if (!found && o.userData?.subject === c.follow) found = o; });
  if (!found) return;
  const p = new THREE.Vector3();
  found.getWorldPosition(p);
  const offset = c.camera.position.clone().sub(c.target);
  c.target.copy(p);
  c.camera.position.copy(p.clone().add(offset));
  c.camera.lookAt(c.target);
}

/* A minimal orbit: drag to rotate, wheel to dolly. three's own OrbitControls
 * lives in examples/ and pulling it in is a bigger dependency than the twenty
 * lines it would save. */
function orbit(pane, c) {
  let drag = null;
  //  Left button only: a right-click starting an orbit means the scene spins
  //  as soon as the context menu closes. (The 2D pane had the same bug.)
  pane.addEventListener('pointerdown', (e) => {
    /*  Not on a control. The pane captures the pointer for the drag, and a
     *  captured pointer delivers its `click` to the capturing element rather
     *  than to the button under it — so a toolbar button pressed here would
     *  simply never fire. */
    //  …and not on the scene STRIP, which shares this pane when "split into
    //  scenes" is on: a captured pointer delivers its click here instead of to
    //  the frame the reader aimed at.
    if (e.button !== 0 || e.target.closest('.vp-controls, .scene-tools, .scene-legend, .strip')) return;
    drag = { x: e.clientX, y: e.clientY, pos: c.camera.position.clone() };
    try { pane.setPointerCapture(e.pointerId); } catch { /* not capturable */ }
  });
  pane.addEventListener('pointermove', (e) => {
    if (!drag) return;
    c.userMoved = true;
    const dx = (e.clientX - drag.x) * 0.01, dy = (e.clientY - drag.y) * 0.01;
    const v = drag.pos.clone().sub(c.target);
    const r = v.length();
    let theta = Math.atan2(v.x, v.z) - dx;
    let phi = Math.acos(Math.max(-1, Math.min(1, v.y / r))) + dy;
    phi = Math.max(0.15, Math.min(Math.PI - 0.15, phi));
    c.camera.position.set(
      c.target.x + r * Math.sin(phi) * Math.sin(theta),
      c.target.y + r * Math.cos(phi),
      c.target.z + r * Math.sin(phi) * Math.cos(theta));
    c.camera.lookAt(c.target);
  });
  const stop = () => { drag = null; };
  pane.addEventListener('pointerup', stop);
  pane.addEventListener('pointerleave', stop);
  pane.addEventListener('pointercancel', stop);
  pane.addEventListener('contextmenu', stop);
  pane.addEventListener('wheel', (e) => {
    if (e.target.closest('.strip')) return;             // the strip scrolls
    e.preventDefault();
    c.userMoved = true;
    const v = c.camera.position.clone().sub(c.target);
    v.multiplyScalar(Math.exp(e.deltaY * 0.001));
    if (v.length() > 1 && v.length() < 300) c.camera.position.copy(c.target.clone().add(v));
    c.camera.lookAt(c.target);
  }, { passive: false });
}

function controls(pane, c) {
  pane.classList.add('vp-host');
  const box = document.createElement('div');
  box.className = 'vp-controls';
  const mk = (t, title, fn) => {
    const b = document.createElement('button');
    b.textContent = t; b.title = title;
    b.addEventListener('click', (e) => { e.stopPropagation(); fn(); });
    box.appendChild(b);
  };
  const dolly = (f) => {
    c.userMoved = true;
    const v = c.camera.position.clone().sub(c.target).multiplyScalar(f);
    c.camera.position.copy(c.target.clone().add(v));
    c.camera.lookAt(c.target);
  };
  mk('+', 'Zoom in (or scroll)', () => dolly(0.8));
  mk('−', 'Zoom out (or scroll)', () => dolly(1.25));
  /*  Fit, not "restore".
   *
   *  Reset used to put the camera back where `display3d(timeless, …)` asked
   *  for — which is right only if the program's camera happens to frame its
   *  own scene, and a hand-written `position:[7,5,10]` usually does not once
   *  the objects move. What a reset button is *for* is getting everything back
   *  on screen, so: measure what is there and back off far enough to see it,
   *  along whatever direction the declared camera chose. */
  mk('⤢', 'Fit everything in view (double-click the scene does the same)', () => fitView(c));
  /*  Three glyphs with no words is a puzzle. The mouse is the *other* half of
   *  the controls and nothing said so anywhere. */
  const legend = document.createElement('span');
  legend.className = 'muted mouse-legend';
  //  Not "right-click: why?" as well — the pane header says that already, for
  //  every pane, and saying it twice on one screen makes both copies noise.
  legend.textContent = 'drag: rotate · shift-drag: pan · scroll: zoom';
  box.appendChild(legend);
  pane.appendChild(box);
}



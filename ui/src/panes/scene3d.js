/* scene3d.js — the 3D pane, on three.js (M15c).
 *
 * Driven by `display3d/2`, a *new* declaration rather than a reinterpretation
 * of `display/2`. Two-dimensional props do not carry into three dimensions
 * without lying about what the author meant — `from`/`to` says "a rectangle
 * between these corners", which in 3D could be a box, a plane or a wall — and
 * a program may reasonably want both mappings at once, showing different
 * things.
 *
 * The declaration, documented in docs/lps_summary.md:
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
import * as THREE from 'three';

let ctx = null;

const num = (v, d) => (typeof v === 'number' ? v : (typeof v === 'string' && v !== '' && !isNaN(+v) ? +v : d));
const vec = (p, k, d) => (Array.isArray(p[k]) ? p[k].map((n) => num(n, 0)) : d);
const colour = (v, d) => {
  if (v === undefined || v === null) return d;
  if (Array.isArray(v)) return new THREE.Color(num(v[0], 0), num(v[1], 0), num(v[2], 0));
  try { return new THREE.Color(String(v)); } catch { return new THREE.Color(d); }
};

function material(p) {
  const m = new THREE.MeshStandardMaterial({
    color: colour(p.color ?? p.fillColor, '#7aa2f7'),
    roughness: num(p.roughness, 0.65),
    metalness: num(p.metalness, 0.05),
    transparent: p.opacity !== undefined && num(p.opacity, 1) < 1,
    opacity: num(p.opacity, 1),
  });
  return m;
}

function build(p) {
  const type = String(p.type || 'box').toLowerCase();
  const size = vec(p, 'size', null);
  let mesh = null;
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
      if (type === 'ground') mesh.rotation.x = -Math.PI / 2;
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
    case 'text': {
      //  A sprite rather than real geometry: no font loading, always legible,
      //  and it faces the camera, which is what a label wants to do.
      const text = String(p.label ?? p.content ?? '');
      const cvs = document.createElement('canvas');
      const ctx2 = cvs.getContext('2d');
      ctx2.font = 'bold 48px system-ui, sans-serif';
      cvs.width = Math.max(64, ctx2.measureText(text).width + 24); cvs.height = 64;
      const c2 = cvs.getContext('2d');
      c2.font = 'bold 48px system-ui, sans-serif';
      c2.fillStyle = String(p.color ?? '#e8e8e8');
      c2.textBaseline = 'middle';
      c2.fillText(text, 12, 34);
      const tex = new THREE.CanvasTexture(cvs);
      const sp = new THREE.Sprite(new THREE.SpriteMaterial({ map: tex, transparent: true }));
      const s = num(p.scale, 1);
      sp.scale.set((cvs.width / 64) * s, s, 1);
      return sp;
    }
    default:
      return null;
  }
  return mesh;
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

export function renderScene3d(pane, data, cycle) {
  const timeless = data.timeless || [];
  const items = data.items || [];
  if (!timeless.length && !items.length) {
    const p = document.createElement('p');
    p.className = 'empty';
    p.textContent = 'This program declares no display3d/2 clauses. '
      + 'The assistant can write them: “Animate in 3D”.';
    pane.replaceChildren(p);
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
    const renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true });
    renderer.setPixelRatio(Math.min(devicePixelRatio, 2));
    renderer.setSize(host.clientWidth || 600, host.clientHeight || 420);
    host.appendChild(renderer.domElement);
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(50, (pane.clientWidth || 600) / (pane.clientHeight || 420), 0.1, 500);
    camera.position.set(14, 12, 16);
    camera.lookAt(0, 0, 0);
    ctx = { pane, host, renderer, scene, camera, objects: new Map(), stop: false, target: new THREE.Vector3(0, 0, 0) };
    orbit(pane, ctx);
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
      ctx.renderer.render(ctx.scene, ctx.camera);
      requestAnimationFrame(loop);
    };
    loop();
  }

  const { scene } = ctx;
  scene.clear();
  scene.add(new THREE.AmbientLight(0xffffff, 0.55));

  let sawLight = false;
  const addProps = (p, key) => {
    const type = String(p.type || '').toLowerCase();
    if (type === 'camera') {
      const at = vec(p, 'position', [14, 12, 16]);
      ctx.camera.position.set(...at);
      const look = vec(p, 'lookAt', [0, 0, 0]);
      ctx.target.set(...look);
      ctx.camera.lookAt(ctx.target);
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
    if (p.label && String(p.type).toLowerCase() !== 'text') {
      const lab = build({ type: 'text', label: p.label, scale: num(p.labelScale, 0.9) });
      const at = vec(p, 'position', [0, 0, 0]);
      lab.position.set(at[0], (at[1] ?? 0) + (vec(p, 'size', [1, 1, 1])[1] ?? 1) * 0.7 + 0.6, at[2]);
      scene.add(lab);
    }
  };

  for (const p of timeless) addProps(p, null);
  for (const it of items) addProps(it.props, it.subject);
  if (!sawLight) {
    const l = new THREE.DirectionalLight(0xffffff, 1.1);
    l.position.set(10, 16, 8);
    scene.add(l);
  }
  return { cycle };
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

/* A minimal orbit: drag to rotate, wheel to dolly. three's own OrbitControls
 * lives in examples/ and pulling it in is a bigger dependency than the twenty
 * lines it would save. */
function orbit(pane, c) {
  let drag = null;
  pane.addEventListener('pointerdown', (e) => {
    if (e.target.closest('.vp-controls')) return;
    drag = { x: e.clientX, y: e.clientY, pos: c.camera.position.clone() };
  });
  pane.addEventListener('pointermove', (e) => {
    if (!drag) return;
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
  pane.addEventListener('wheel', (e) => {
    e.preventDefault();
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
    const v = c.camera.position.clone().sub(c.target).multiplyScalar(f);
    c.camera.position.copy(c.target.clone().add(v));
    c.camera.lookAt(c.target);
  };
  mk('+', 'Closer', () => dolly(0.8));
  mk('−', 'Further', () => dolly(1.25));
  mk('⤢', 'Reset view', () => {
    c.target.set(0, 0, 0);
    c.camera.position.set(14, 12, 16);
    c.camera.lookAt(c.target);
  });
  pane.appendChild(box);
}

/* models3d.js — the 3D object catalogue: `[type:model, model:tree]`.
 *
 * The icons gave a 2D scene things that look like what they are. This is that
 * for three dimensions, and it is BUILT rather than downloaded — see
 * ui/models3d/manifest.json for why, and for the CC0 mesh libraries that are
 * the alternative if photoreal objects are ever wanted.
 *
 * Every model is a THREE.Group of primitives, one unit wide and roughly one
 * unit tall, standing on y = 0 so that a thing placed at a slab's centre sits
 * on it rather than in it. Each takes the object's own `color`, so a scene
 * keeps one palette: the shapes say *what*, the colours say *which*.
 *
 * Adding one is a function here and a row in the manifest. The two are checked
 * against each other by `missingModels()`, which the IDE's own check calls.
 */
import * as THREE from 'three';
import manifest from '../models3d/manifest.json';

export const models = manifest.models.map(({ name, desc, concepts }) => ({ name, desc, concepts }));

const mat = (c, o = {}) => new THREE.MeshStandardMaterial({
  color: c, roughness: o.roughness ?? 0.7, metalness: o.metalness ?? 0.05,
  transparent: o.opacity !== undefined && o.opacity < 1, opacity: o.opacity ?? 1,
});

//  A shade of the object's own colour, so one model can have parts without
//  needing a second colour from the author.
const shade = (c, k) => new THREE.Color(c).multiplyScalar(k);

const box = (w, h, d, c, x = 0, y = 0, z = 0) => {
  const m = new THREE.Mesh(new THREE.BoxGeometry(w, h, d), mat(c));
  m.position.set(x, y, z);
  return m;
};
const cyl = (r1, r2, h, c, x = 0, y = 0, z = 0, seg = 16) => {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(r1, r2, h, seg), mat(c));
  m.position.set(x, y, z);
  return m;
};
const ball = (r, c, x = 0, y = 0, z = 0) => {
  const m = new THREE.Mesh(new THREE.SphereGeometry(r, 18, 12), mat(c));
  m.position.set(x, y, z);
  return m;
};
const cone = (r, h, c, x = 0, y = 0, z = 0) => {
  const m = new THREE.Mesh(new THREE.ConeGeometry(r, h, 18), mat(c));
  m.position.set(x, y, z);
  return m;
};
const wheel = (r, c, x, y, z) => {
  const m = cyl(r, r, 0.14, shade(c, 0.35), x, y, z, 14);
  m.rotation.z = Math.PI / 2;
  return m;
};
const group = (...parts) => {
  const g = new THREE.Group();
  for (const p of parts) if (p) g.add(p);
  return g;
};

/* Each builder takes the object's colour and returns a group standing on y=0.
 * Kept deliberately blunt: these read at thumbnail size, which is the size a
 * scene shows them at. */
const BUILD = {
  person: (c) => group(cyl(0.16, 0.2, 0.5, c, 0, 0.25, 0), ball(0.17, shade(c, 1.25), 0, 0.68, 0),
    box(0.5, 0.08, 0.12, c, 0, 0.45, 0)),
  robot: (c) => group(box(0.42, 0.42, 0.3, c, 0, 0.36, 0), box(0.3, 0.24, 0.24, shade(c, 1.3), 0, 0.72, 0),
    cyl(0.02, 0.02, 0.18, shade(c, 1.5), 0, 0.9, 0), box(0.1, 0.32, 0.1, shade(c, 0.7), -0.26, 0.34, 0),
    box(0.1, 0.32, 0.1, shade(c, 0.7), 0.26, 0.34, 0), box(0.14, 0.16, 0.14, shade(c, 0.6), -0.12, 0.08, 0),
    box(0.14, 0.16, 0.14, shade(c, 0.6), 0.12, 0.08, 0)),
  animal: (c) => group(box(0.56, 0.28, 0.24, c, 0, 0.44, 0), box(0.22, 0.2, 0.2, shade(c, 1.2), 0.36, 0.56, 0),
    cyl(0.05, 0.05, 0.3, shade(c, 0.8), -0.2, 0.15, 0.09), cyl(0.05, 0.05, 0.3, shade(c, 0.8), 0.2, 0.15, 0.09),
    cyl(0.05, 0.05, 0.3, shade(c, 0.8), -0.2, 0.15, -0.09), cyl(0.05, 0.05, 0.3, shade(c, 0.8), 0.2, 0.15, -0.09)),
  bird: (c) => group(ball(0.18, c, 0, 0.3, 0), cone(0.07, 0.16, shade(c, 1.4), 0.2, 0.32, 0),
    box(0.34, 0.04, 0.14, shade(c, 0.8), -0.05, 0.34, 0), cyl(0.02, 0.02, 0.2, shade(c, 0.6), 0, 0.1, 0)),
  tree: (c) => group(cyl(0.07, 0.09, 0.4, shade(c, 0.45), 0, 0.2, 0),
    cone(0.32, 0.5, c, 0, 0.62, 0), cone(0.24, 0.4, shade(c, 1.15), 0, 0.92, 0)),
  house: (c) => group(box(0.7, 0.5, 0.6, c, 0, 0.25, 0),
    (() => { const r = cone(0.56, 0.36, shade(c, 0.7), 0, 0.68, 0); r.rotation.y = Math.PI / 4; return r; })(),
    box(0.16, 0.26, 0.02, shade(c, 0.5), 0, 0.13, 0.31)),
  bank: (c) => group(box(0.8, 0.12, 0.6, shade(c, 0.8), 0, 0.06, 0),
    ...[-0.3, -0.1, 0.1, 0.3].map((x) => cyl(0.06, 0.06, 0.44, c, x, 0.34, 0.24)),
    box(0.8, 0.1, 0.6, shade(c, 0.9), 0, 0.61, 0),
    (() => { const r = cone(0.5, 0.2, shade(c, 0.7), 0, 0.76, 0); r.rotation.y = Math.PI / 4; return r; })()),
  hospital: (c) => group(box(0.7, 0.6, 0.6, c, 0, 0.3, 0),
    box(0.3, 0.09, 0.02, '#ffffff', 0, 0.42, 0.31), box(0.09, 0.3, 0.02, '#ffffff', 0, 0.42, 0.31)),
  factory: (c) => group(box(0.8, 0.4, 0.5, c, 0, 0.2, 0),
    cyl(0.09, 0.09, 0.55, shade(c, 0.7), 0.28, 0.5, 0),
    box(0.2, 0.16, 0.5, shade(c, 1.2), -0.2, 0.48, 0)),
  car: (c) => group(box(0.7, 0.2, 0.36, c, 0, 0.24, 0), box(0.38, 0.18, 0.32, shade(c, 1.25), -0.02, 0.42, 0),
    wheel(0.12, c, -0.24, 0.12, 0.19), wheel(0.12, c, 0.24, 0.12, 0.19),
    wheel(0.12, c, -0.24, 0.12, -0.19), wheel(0.12, c, 0.24, 0.12, -0.19)),
  truck: (c) => group(box(0.42, 0.3, 0.4, shade(c, 1.2), -0.26, 0.33, 0), box(0.6, 0.34, 0.44, c, 0.22, 0.35, 0),
    box(1.0, 0.1, 0.44, shade(c, 0.7), 0, 0.16, 0),
    wheel(0.13, c, -0.3, 0.13, 0.23), wheel(0.13, c, 0.3, 0.13, 0.23),
    wheel(0.13, c, -0.3, 0.13, -0.23), wheel(0.13, c, 0.3, 0.13, -0.23)),
  train: (c) => group(box(0.9, 0.36, 0.42, c, 0, 0.36, 0), box(0.3, 0.26, 0.4, shade(c, 1.25), -0.28, 0.66, 0),
    cyl(0.07, 0.07, 0.2, shade(c, 0.6), 0.3, 0.64, 0),
    wheel(0.11, c, -0.3, 0.13, 0.22), wheel(0.11, c, 0.05, 0.13, 0.22), wheel(0.11, c, 0.32, 0.13, 0.22),
    wheel(0.11, c, -0.3, 0.13, -0.22), wheel(0.11, c, 0.05, 0.13, -0.22), wheel(0.11, c, 0.32, 0.13, -0.22)),
  boat: (c) => group(box(0.8, 0.2, 0.34, c, 0, 0.12, 0), cyl(0.03, 0.03, 0.6, shade(c, 0.5), -0.05, 0.5, 0),
    (() => { const s = new THREE.Mesh(new THREE.ConeGeometry(0.26, 0.5, 3), mat(shade(c, 1.4)));
      s.position.set(0.1, 0.5, 0); s.rotation.y = Math.PI / 2; return s; })()),
  plane: (c) => group(cyl(0.1, 0.06, 0.8, c, 0, 0.4, 0, 12).rotateZ(Math.PI / 2),
    box(0.16, 0.03, 0.8, shade(c, 1.2), 0, 0.4, 0), box(0.14, 0.2, 0.03, shade(c, 1.2), -0.34, 0.5, 0)),
  box: (c) => group(box(0.5, 0.5, 0.5, c, 0, 0.25, 0), box(0.52, 0.03, 0.06, shade(c, 0.6), 0, 0.5, 0)),
  crate: (c) => group(box(0.5, 0.5, 0.5, c, 0, 0.25, 0),
    box(0.54, 0.05, 0.05, shade(c, 0.55), 0, 0.12, 0.25), box(0.54, 0.05, 0.05, shade(c, 0.55), 0, 0.38, 0.25),
    box(0.05, 0.54, 0.05, shade(c, 0.55), -0.24, 0.25, 0.25), box(0.05, 0.54, 0.05, shade(c, 0.55), 0.24, 0.25, 0.25)),
  barrel: (c) => group(cyl(0.22, 0.22, 0.5, c, 0, 0.25, 0), cyl(0.24, 0.24, 0.05, shade(c, 0.6), 0, 0.14, 0),
    cyl(0.24, 0.24, 0.05, shade(c, 0.6), 0, 0.36, 0)),
  bag: (c) => group(ball(0.26, c, 0, 0.26, 0), cyl(0.1, 0.16, 0.14, shade(c, 0.8), 0, 0.5, 0)),
  coin: (c) => group((() => { const m = cyl(0.26, 0.26, 0.06, c, 0, 0.26, 0, 24); m.rotation.x = Math.PI / 2; return m; })()),
  key: (c) => group((() => { const r = new THREE.Mesh(new THREE.TorusGeometry(0.13, 0.04, 10, 20), mat(c));
      r.position.set(-0.2, 0.2, 0); return r; })(),
    box(0.4, 0.06, 0.06, c, 0.08, 0.2, 0), box(0.06, 0.14, 0.06, c, 0.22, 0.13, 0)),
  door: (c) => group(box(0.06, 0.8, 0.44, shade(c, 0.6), -0.2, 0.4, 0),
    box(0.06, 0.72, 0.36, c, 0, 0.36, 0), ball(0.04, shade(c, 1.5), 0.05, 0.36, 0.14)),
  flag: (c) => group(cyl(0.03, 0.03, 0.9, shade(c, 0.5), 0, 0.45, 0),
    box(0.02, 0.24, 0.36, c, 0.02, 0.74, 0.18)),
  sign: (c) => group(cyl(0.035, 0.035, 0.7, shade(c, 0.5), 0, 0.35, 0), box(0.04, 0.3, 0.5, c, 0, 0.72, 0)),
  table: (c) => group(box(0.8, 0.06, 0.5, c, 0, 0.44, 0),
    ...[[-0.35, 0.2], [0.35, 0.2], [-0.35, -0.2], [0.35, -0.2]].map(([x, z]) => box(0.06, 0.42, 0.06, shade(c, 0.7), x, 0.21, z))),
  chair: (c) => group(box(0.4, 0.05, 0.4, c, 0, 0.42, 0), box(0.4, 0.45, 0.05, shade(c, 1.1), 0, 0.64, -0.18),
    ...[[-0.16, 0.16], [0.16, 0.16], [-0.16, -0.16], [0.16, -0.16]].map(([x, z]) => box(0.05, 0.4, 0.05, shade(c, 0.7), x, 0.2, z))),
  bed: (c) => group(box(0.9, 0.16, 0.5, c, 0, 0.26, 0), box(0.1, 0.4, 0.5, shade(c, 0.7), -0.45, 0.3, 0),
    box(0.3, 0.1, 0.4, '#f0f2f6', -0.26, 0.38, 0)),
  cup: (c) => group(cyl(0.16, 0.12, 0.3, c, 0, 0.15, 0),
    (() => { const h = new THREE.Mesh(new THREE.TorusGeometry(0.09, 0.025, 8, 16), mat(shade(c, 0.8)));
      h.position.set(0.2, 0.17, 0); return h; })()),
  book: (c) => group(box(0.44, 0.1, 0.56, c, 0, 0.05, 0), box(0.4, 0.06, 0.52, '#eceff4', 0.02, 0.09, 0)),
  rock: (c) => group((() => { const m = new THREE.Mesh(new THREE.DodecahedronGeometry(0.3, 0), mat(shade(c, 0.9)));
      m.position.set(0, 0.24, 0); m.rotation.set(0.4, 0.8, 0.2); m.scale.set(1, 0.8, 1.1); return m; })()),
  cloud: (c) => group(ball(0.24, c, -0.18, 0.6, 0), ball(0.3, c, 0.06, 0.66, 0), ball(0.2, c, 0.3, 0.58, 0)),
  fire: (c) => group(cone(0.22, 0.5, c, 0, 0.25, 0), cone(0.13, 0.3, shade(c, 1.5), 0, 0.18, 0.02)),
  bulb: (c) => group(ball(0.22, c, 0, 0.42, 0), cyl(0.1, 0.12, 0.16, shade(c, 0.5), 0, 0.14, 0)),
  tower: (c) => group(cyl(0.22, 0.32, 0.9, c, 0, 0.45, 0, 8), cyl(0.3, 0.3, 0.1, shade(c, 0.7), 0, 0.92, 0, 8),
    cone(0.26, 0.24, shade(c, 1.2), 0, 1.08, 0, 8)),
  arrow: (c) => group(box(0.5, 0.06, 0.12, c, -0.1, 0.06, 0),
    (() => { const h = cone(0.16, 0.3, c, 0.3, 0.06, 0); h.rotation.z = -Math.PI / 2; return h; })()),
};

export const hasModel = (name) => Object.prototype.hasOwnProperty.call(BUILD, String(name));

/** Names in the manifest with no builder here (and the other way round). */
export function missingModels() {
  const built = new Set(Object.keys(BUILD));
  const listed = new Set(models.map((m) => m.name));
  return {
    unbuilt: [...listed].filter((n) => !built.has(n)),
    unlisted: [...built].filter((n) => !listed.has(n)),
  };
}

/**
 * Build one, or null when the name is not ours.
 *   props  the display3d properties: `color`, `scale`, `opacity`.
 */
export function buildModel(name, props = {}) {
  const f = BUILD[String(name)];
  if (!f) return null;
  const colour = props.color ?? props.fillColor ?? '#7aa2f7';
  let g;
  try { g = f(new THREE.Color(colour)); } catch { g = f(new THREE.Color('#7aa2f7')); }
  const s = typeof props.scale === 'number' ? props.scale
    : (typeof props.scale === 'string' && props.scale !== '' && !isNaN(+props.scale) ? +props.scale : 1);
  if (s !== 1) g.scale.setScalar(s);
  if (props.opacity !== undefined) {
    const o = Number(props.opacity);
    if (!isNaN(o) && o < 1) {
      g.traverse((n) => { if (n.material) { n.material.transparent = true; n.material.opacity = o; } });
    }
  }
  return g;
}

/** Ranked matches for a word — how the assistant picks an object by meaning. */
export function suggestModels(word, limit = 5) {
  const w = String(word || '').toLowerCase().replace(/[^a-z0-9]+/g, '');
  if (!w) return [];
  const score = (m) => {
    let best = 0;
    for (const c of [m.name, ...(m.concepts || []), m.desc]) {
      const t = String(c).toLowerCase().replace(/[^a-z0-9]+/g, '');
      if (!t) continue;
      if (t === w) best = Math.max(best, 100);
      else if (w.startsWith(t) || t.startsWith(w)) best = Math.max(best, 70);
      else if (w.includes(t) || t.includes(w)) best = Math.max(best, 40);
    }
    return best;
  };
  return models.map((m) => ({ m, s: score(m) })).filter((x) => x.s > 0)
    .sort((a, b) => b.s - a.s).slice(0, limit).map((x) => x.m);
}

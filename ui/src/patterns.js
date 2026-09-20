/* patterns.js — the fill library: tiles for the surfaces of a scene.
 *
 * `display(F, [type:rectangle, fillColor:'#2f3542', pattern:hatch, …])` and
 * `display3d(F, [type:box, color:teal, pattern:bricks, …])` name one of these.
 * The icons say what a thing *is*; a pattern says what a surface is *like* —
 * hatched for unavailable, bricks for built, waves for water — and it is the
 * one visual distinction a scene of flat rectangles could not make at all.
 *
 * Two properties of the design are worth stating, because both are unusual:
 *
 *   * **the tile takes the shape's colours.** Each tile is an SVG with two
 *     placeholders, `__INK__` and `__BG__`, filled in here from the object's
 *     own `fillColor`/`color` and the pattern's ink. So one tile serves every
 *     colour in the scene, and a pattern never fights the palette.
 *   * **nothing is fetched.** The tiles are in ui/patterns/manifest.json, a
 *     few hundred bytes each, and become `data:` URLs — so they work offline,
 *     draw on the first frame, and need no endpoint of their own.
 *
 * The same tile is a Konva fill in two dimensions and a three.js texture in
 * three, which is what keeps a 2D scene and its 3D twin recognisably the same
 * picture.
 */
import manifest from '../patterns/manifest.json';

export const patterns = manifest.patterns.map(({ name, desc, concepts }) => ({ name, desc, concepts }));

const byName = new Map(manifest.patterns.map((p) => [p.name, p]));

export const hasPattern = (name) => byName.has(String(name));

/** The tile as an SVG string, inked and backed. */
export function patternSvg(name, ink = '#8b94a6', bg = 'transparent') {
  const p = byName.get(String(name));
  if (!p) return null;
  return p.svg.replace(/__INK__/g, ink).replace(/__BG__/g, bg);
}

/** …as a data: URL. Cached: a scene draws the same tile many times. */
const urls = new Map();
export function patternUrl(name, ink, bg) {
  const key = `${name}|${ink}|${bg}`;
  if (urls.has(key)) return urls.get(key);
  const svg = patternSvg(name, ink, bg);
  if (!svg) return null;
  const url = 'data:image/svg+xml;utf8,' + encodeURIComponent(svg);
  urls.set(key, url);
  return url;
}

/** …as an <img>, for Konva's fillPatternImage. `onload` re-draws the layer. */
const images = new Map();
export function patternImage(name, ink, bg, onload) {
  const key = `${name}|${ink}|${bg}`;
  if (images.has(key)) return images.get(key);
  const url = patternUrl(name, ink, bg);
  if (!url) return null;
  const img = new Image();
  img.onload = () => { if (onload) onload(); };
  img.src = url;
  images.set(key, img);
  return img;
}

/** Ranked matches for a word — how the assistant picks a fill by meaning. */
export function suggestPatterns(word, limit = 5) {
  const w = String(word || '').toLowerCase().replace(/[^a-z0-9]+/g, '');
  if (!w) return [];
  const score = (p) => {
    let best = 0;
    for (const c of [p.name, ...(p.concepts || []), p.desc]) {
      const t = String(c).toLowerCase().replace(/[^a-z0-9]+/g, '');
      if (!t) continue;
      if (t === w) best = Math.max(best, 100);
      else if (w.startsWith(t) || t.startsWith(w)) best = Math.max(best, 70);
      else if (w.includes(t) || t.includes(w)) best = Math.max(best, 40);
    }
    return best;
  };
  return patterns.map((p) => ({ p, s: score(p) })).filter((x) => x.s > 0)
    .sort((a, b) => b.s - a.s).slice(0, limit).map((x) => x.p);
}

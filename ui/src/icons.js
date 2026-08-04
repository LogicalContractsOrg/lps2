/* icons.js — the icon library (§I.10.4b).
 *
 * `display(F, [type:raster, icon:goat, ...])` is the point of this: a program
 * about goats and cabbages should be able to look like goats and cabbages
 * without the author hunting for a URL, and without the animation breaking the
 * day that URL rots — which is exactly what happened to the corpus, whose
 * light-bulb raster is a dead clker.com link.
 *
 * The files are served from our own endpoint (ui/static/icons, fetched by
 * ui/fetch-icons.mjs), so this works offline. `source:` still accepts a URL,
 * because the corpus is full of them.
 */
import { iconIndex, iconLicenses } from './generated/icon-index.js';

export const icons = iconIndex;
export const licenses = iconLicenses;

const byName = new Map(iconIndex.map((i) => [i.name, i]));

export const iconUrl = (name) => (byName.has(name) ? `/assets/icons/${name}.svg` : null);

/** props → an image URL, preferring the library over a remote link. */
export function resolveIcon(props) {
  if (props.icon) {
    const u = iconUrl(String(props.icon));
    if (u) return u;
  }
  if (props.source) {
    const s = String(props.source);
    //  `source:goat` is accepted as a library name too: it is what an author
    //  writes by mistake, and doing what they meant costs one line.
    return /^(https?:|data:|\.|\/)/.test(s) ? s : (iconUrl(s) || s);
  }
  return null;
}

/** Ranked matches for a word — how the assistant picks an icon by meaning. */
export function suggestIcons(word, limit = 5) {
  const w = String(word || '').toLowerCase().replace(/[^a-z0-9]+/g, '');
  if (!w) return [];
  const score = (i) => {
    let best = 0;
    for (const c of [i.name, ...(i.concepts || []), i.desc]) {
      const t = String(c).toLowerCase().replace(/[^a-z0-9]+/g, '');
      if (!t) continue;
      if (t === w) best = Math.max(best, 100);
      else if (w.startsWith(t) || t.startsWith(w)) best = Math.max(best, 70);
      else if (w.includes(t) || t.includes(w)) best = Math.max(best, 40);
    }
    return best;
  };
  return iconIndex
    .map((i) => ({ icon: i, s: score(i) }))
    .filter((x) => x.s > 0)
    .sort((a, b) => b.s - a.s)
    .slice(0, limit)
    .map((x) => x.icon);
}

/** The whole catalogue as prompt material: name — description — concepts. */
export function iconCatalogueText() {
  return iconIndex.map((i) => `${i.name}: ${i.desc} (${(i.concepts || []).join(', ')})`).join('\n');
}

/* comic.js — the Comics pane: one run, told as a comic strip.
 *
 * The Timeline shows what happened. This pane tells it: one panel for the
 * start, one for each cycle in which something happened, one for the end. It
 * also draws three things that the Timeline does not have:
 *
 *   - the latent actors. A reactive rule, a causal law and an integrity
 *     constraint each do something in a run, and the program names none of
 *     them as an actor. Here a rule with no agent is a dashed ghost marked
 *     IF, the causal laws are a dashed ghost marked ±, and a constraint is a
 *     dashed guard with a "no" sign (black, or red, when it refuses);
 *   - what was refused: an action that a constraint blocked;
 *   - in the exploratory story, what did not happen (out of focus).
 *
 * Who does what:
 *
 *   the server   `story`: the panels and their facts, from the trace, with a
 *                computed caption for each. `story_words`: a title, a figure
 *                for each name, a name for each latent actor and a caption
 *                for each panel, from a small model, checked against the
 *                facts (src/edges/lps_story.pl).
 *   this file    everything about the picture. Which figures stand in a
 *                panel and where, the balloons, their tails, the timeline at
 *                the foot. A panel is laid out by the browser (boxes that
 *                flow do not overlap) and each figure has a slot of its own,
 *                so no model and no person has to place anything.
 *
 * Nobody speaks words that a model wrote. A balloon of a named actor is the
 * event itself: its sentence when the document is Logical English, its term
 * otherwise. A balloon of a latent actor is the text of its clause.
 *
 * The experiment this comes from: lpsPlus docs/reports/ProgramStoriesExperiment.md.
 */
import { askable } from '../why.js';

const NS = 'http://www.w3.org/2000/svg';
const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/"/g, '&quot;');
const cap1 = (s) => (s ? s.charAt(0).toUpperCase() + s.slice(1) : s);
const clip = (s, n) => (s.length > n ? s.slice(0, n - 1).trimEnd() + '…' : s);

/*  One tint for each named actor, when the reader asks for colour. Light
 *  enough for black ink to stay the line. */
const TINTS = ['#ffd27f', '#9fd3ff', '#b8e6a0', '#f4b6d6', '#d7c3ff', '#ffb199', '#a8e6de', '#e8e08a', '#c9d1ff', '#f7c6a3'];

/* ------------------------------------------------------------ small drawing */
const limb = (pts, w = 15) =>
  `<polyline points="${pts}" fill="none" stroke="#000" stroke-width="${w}" stroke-linecap="round" stroke-linejoin="round"/>` +
  `<polyline class="b" points="${pts}" fill="none" stroke="#fff" stroke-width="${w - 7}" stroke-linecap="round" stroke-linejoin="round" style="fill:none;stroke:var(--fig,#fff)"/>`;
const W = 'class="b" fill="#fff" stroke="#000"';            // a part of the body: takes the actor's tint
const noSign = (x, y, r, on) =>
  `<circle class="${on ? 'no' : ''}" cx="${x}" cy="${y}" r="${r}" fill="${on ? '#000' : '#fff'}" stroke="#000" stroke-width="${on ? 3 : 2.5}"${on ? '' : ' stroke-dasharray="5 4"'}/>` +
  `<rect x="${x - r * 0.62}" y="${y - r * 0.2}" width="${r * 1.24}" height="${r * 0.4}" fill="${on ? '#fff' : '#000'}"/>`;
const letter = (o, y, size, fill = '#000') => (o.letter
  ? `<text x="0" y="${y}" text-anchor="middle" font-family="Impact,'Arial Narrow',sans-serif" font-size="${size}" fill="${fill}">${esc(o.letter)}</text>` : '');

function personSvg(o) {
  const legs = o.dress
    ? `<path ${W} stroke-width="4" stroke-linejoin="round" d="M-26,-92 L-46,-22 L46,-22 L26,-92 Z"/><path d="M-14,-22 L-14,0 M14,-22 L14,0" stroke="#000" stroke-width="7" stroke-linecap="round"/>`
    : `<polygon ${W} stroke-width="4" points="-28,-84 -40,0 -12,0 -3,-84"/><polygon ${W} stroke-width="4" points="3,-84 12,0 40,0 28,-84"/>` +
      `<polygon points="-36,-22 -42,0 -8,0 -9,-22"/><polygon points="9,-22 8,0 42,0 36,-22"/>`;
  const torso = `<polygon ${W} stroke-width="4" stroke-linejoin="round" points="-42,-152 42,-152 27,-80 -27,-80"/><rect x="-28" y="-90" width="56" height="12"/>`;
  const arms = o.pose === 'point'
    ? limb('-40,-146 -66,-112 -32,-90') + limb('40,-146 84,-160 128,-176') + `<circle ${W} cx="132" cy="-178" r="11" stroke-width="4"/>`
    : limb('-40,-146 -68,-112 -32,-90') + limb('40,-146 68,-112 32,-90');
  let head = `<rect x="-9" y="-160" width="18" height="12" fill="#fff" stroke="#000" stroke-width="3"/>` +
    `<path d="M-19,-186 C-19,-204 19,-204 19,-186 L16,-166 C10,-156 -10,-156 -16,-166 Z" fill="#fff" stroke="#000" stroke-width="4" stroke-linejoin="round"/>` +
    `<circle cx="-5" cy="-180" r="2.8"/><circle cx="9" cy="-180" r="2.8"/><path d="M-4,-169 Q3,-164 10,-169" fill="none" stroke="#000" stroke-width="2.5"/>`;
  head += o.dress
    ? `<path d="M-22,-184 C-26,-216 26,-216 22,-184 L26,-150 L16,-156 L18,-186 C8,-196 -8,-196 -18,-186 L-16,-156 L-26,-150 Z"/>`
    : `<path d="M-21,-186 C-22,-212 22,-212 21,-186 C12,-196 -2,-196 -8,-190 C-12,-194 -18,-190 -21,-186 Z"/>`;
  return legs + torso + letter(o, -108, 34) + arms + head;
}

/*  Every figure has its feet at 0,0. h is its height: a balloon tail points
 *  just above it. A figure marked `latent` is somebody the program does not
 *  name, and is drawn with a dashed line whatever the colours are. */
const FIGS = {
  person: { h: 208, draw: (o) => personSvg(o) },
  woman: { h: 212, draw: (o) => personSvg({ ...o, dress: true }) },
  child: { h: 150, draw: (o) => `<g transform="scale(.72)">${personSvg(o)}</g>` },
  animal: { h: 120, draw: () =>
    `<path d="M-62,-70 C-90,-80 -92,-112 -76,-118" fill="none" stroke="#000" stroke-width="7" stroke-linecap="round"/>` +
    `<path d="M-50,0 L-48,-44 M-26,0 L-28,-40 M24,0 L26,-40 M46,0 L44,-44" stroke="#000" stroke-width="9" stroke-linecap="round"/>` +
    `<ellipse ${W} cx="-4" cy="-62" rx="62" ry="30" stroke-width="4"/>` +
    `<path ${W} stroke-width="4" stroke-linejoin="round" d="M40,-76 C40,-112 84,-118 96,-94 L112,-86 L96,-72 C84,-60 52,-58 40,-76 Z"/>` +
    `<polygon points="50,-100 46,-126 66,-108"/><circle cx="84" cy="-94" r="3.4"/><circle cx="109" cy="-86" r="4.5"/>` },
  fox: { h: 176, draw: () =>
    `<path d="M-44,-6 C-118,-2 -132,-84 -84,-118 C-92,-76 -70,-44 -34,-40 Z"/>` +
    `<path d="M-84,-118 C-100,-104 -106,-84 -100,-66 C-92,-84 -88,-100 -84,-118 Z" fill="#fff" stroke="#000" stroke-width="2"/>` +
    `<path ${W} stroke-width="4" stroke-linejoin="round" d="M-56,0 C-76,-58 -36,-104 6,-116 L40,-108 C44,-62 30,-22 38,0 Z"/>` +
    `<path d="M8,0 L10,-46 M38,0 L32,-52" stroke="#000" stroke-width="4" stroke-linecap="round"/><path d="M-56,0 L46,0" stroke="#000" stroke-width="4" stroke-linecap="round"/>` +
    `<polygon points="2,-150 4,-178 26,-158"/><polygon points="24,-158 36,-176 46,-150"/>` +
    `<path ${W} stroke-width="4" stroke-linejoin="round" d="M-2,-116 C-12,-148 14,-166 40,-154 L92,-124 L46,-102 C30,-94 6,-98 -2,-116 Z"/>` +
    `<circle cx="90" cy="-124" r="6.5"/><path d="M32,-140 L46,-134" stroke="#000" stroke-width="5" stroke-linecap="round"/>` +
    `<path d="M-2,-116 C4,-104 18,-98 30,-98 C22,-108 20,-118 22,-126 Z"/>` },
  bird: { h: 112, draw: () =>
    `<path d="M-6,0 L-2,-22 M16,0 L14,-22" stroke="#000" stroke-width="4" stroke-linecap="round"/>` +
    `<polygon class="bk" points="34,-38 96,-10 88,-34 100,-40 62,-58"/><ellipse class="bk" cx="10" cy="-46" rx="44" ry="30" transform="rotate(-18 10 -46)"/>` +
    `<path d="M-6,-52 C10,-30 40,-30 52,-44" fill="none" stroke="#fff" stroke-width="2.5"/><circle class="bk" cx="-24" cy="-84" r="23"/>` +
    `<polygon points="-42,-94 -90,-82 -42,-72" fill="#fff" stroke="#000" stroke-width="3.5" stroke-linejoin="round"/>` +
    `<circle cx="-28" cy="-90" r="6" fill="#fff"/><circle cx="-30" cy="-90" r="2.6"/>` },
  robot: { h: 190, draw: (o) => `<g transform="scale(1.6)"><rect ${W} x="-30" y="-64" width="60" height="50" rx="10" stroke-width="3"/>${letter(o, -31, 22)}` +
    `<rect ${W} x="-22" y="-100" width="44" height="34" rx="12" stroke-width="3"/><circle cx="-9" cy="-84" r="5"/><circle cx="9" cy="-84" r="5"/><path d="M-8,-74 L8,-74" stroke="#000" stroke-width="2"/>` +
    `<path d="M0,-100 L0,-112" stroke="#000" stroke-width="2.5"/><circle cx="0" cy="-115" r="4.5"/>${limb('-18,-14 -20,0', 10)}${limb('18,-14 20,0', 10)}${limb('-30,-52 -46,-34', 9)}${limb('30,-52 46,-34', 9)}</g>` },
  machine: { h: 140, draw: (o) =>
    `<rect ${W} x="-60" y="-124" width="120" height="116" rx="8" stroke-width="5"/><rect x="-50" y="-8" width="22" height="8"/><rect x="28" y="-8" width="22" height="8"/>` +
    `<circle cx="-24" cy="-78" r="24" fill="#fff" stroke="#000" stroke-width="4" stroke-dasharray="9 5"/><circle cx="-24" cy="-78" r="8"/>` +
    `<circle cx="30" cy="-98" r="7"/><circle cx="30" cy="-74" r="7" fill="#fff" stroke="#000" stroke-width="3"/><rect x="16" y="-52" width="30" height="8"/>${letter(o, -24, 22)}` },
  vehicle: { h: 110, draw: () =>
    `<path ${W} stroke-width="5" stroke-linejoin="round" d="M-92,-24 L-92,-56 L-52,-62 L-30,-98 L40,-98 L62,-62 L92,-54 L92,-24 Z"/>` +
    `<path d="M-24,-90 L-40,-62 L4,-62 L4,-90 Z M14,-90 L14,-62 L50,-62 L34,-90 Z" fill="#fff" stroke="#000" stroke-width="3" stroke-linejoin="round"/>` +
    `<circle cx="-52" cy="-22" r="22"/><circle cx="-52" cy="-22" r="9" fill="#fff"/><circle cx="52" cy="-22" r="22"/><circle cx="52" cy="-22" r="9" fill="#fff"/>` },
  boat: { h: 170, draw: () =>
    `<path ${W} stroke-width="5" stroke-linejoin="round" d="M-90,-48 L90,-48 L64,-8 L-64,-8 Z"/><path d="M0,-48 L0,-166" stroke="#000" stroke-width="6"/>` +
    `<path d="M8,-160 L76,-62 L8,-62 Z" fill="#fff" stroke="#000" stroke-width="4" stroke-linejoin="round"/><path d="M-8,-140 L-58,-62 L-8,-62 Z" fill="url(#cx-dots3)" stroke="#000" stroke-width="4" stroke-linejoin="round"/>` +
    `<path d="M-100,-4 q16,-12 32,0 t32,0 t32,0 t32,0 t32,0 t32,0" fill="none" stroke="#000" stroke-width="4"/>` },
  building: { h: 190, draw: (o) =>
    `<rect ${W} x="-64" y="-132" width="128" height="132" stroke-width="5"/><path d="M-78,-128 L0,-186 L78,-128 Z" stroke="#000" stroke-width="5" stroke-linejoin="round"/>` +
    `<rect x="-16" y="-52" width="32" height="52" fill="#fff" stroke="#000" stroke-width="4"/><circle cx="8" cy="-26" r="3.5"/>` +
    `<rect x="-50" y="-110" width="28" height="28" fill="#fff" stroke="#000" stroke-width="3.5"/><rect x="22" y="-110" width="28" height="28" fill="#fff" stroke="#000" stroke-width="3.5"/>${letter(o, -146, 22, '#fff')}` },
  door: { h: 186, draw: () =>
    `<rect x="-50" y="-180" width="100" height="180" fill="#fff" stroke="#000" stroke-width="6"/><path ${W} stroke-width="5" stroke-linejoin="round" d="M-42,-172 L24,-158 L24,-4 L-42,-4 Z"/><circle cx="10" cy="-84" r="6"/>` },
  safe: { h: 150, draw: (o) =>
    `<rect ${W} x="-62" y="-132" width="124" height="124" rx="6" stroke-width="6"/><rect x="-50" y="-8" width="20" height="8"/><rect x="30" y="-8" width="20" height="8"/>` +
    `<rect x="-50" y="-120" width="100" height="100" fill="url(#cx-dots2)" stroke="#000" stroke-width="3"/><circle cx="14" cy="-84" r="18" fill="#fff" stroke="#000" stroke-width="4"/><path d="M14,-84 L26,-96" stroke="#000" stroke-width="4"/><rect x="-42" y="-100" width="12" height="38"/>` },
  parcel: { h: 74, draw: () =>
    `<rect ${W} x="-42" y="-64" width="84" height="64" stroke-width="4.5" stroke-linejoin="round"/><rect x="-9" y="-64" width="18" height="64" fill="url(#cx-dots3)" stroke="#000" stroke-width="2"/><path d="M-42,-46 L42,-46" stroke="#000" stroke-width="2"/>` },
  paper: { h: 112, draw: () => {
    let l = '';
    for (let i = 0; i < 5; i++) l += `<path d="M-26,${-78 + i * 14} L${i === 4 ? 6 : 26},${-78 + i * 14}" stroke="#000" stroke-width="2.4"/>`;
    return `<path ${W} stroke-width="4" stroke-linejoin="round" d="M-38,-104 L24,-104 L38,-90 L38,0 L-38,0 Z"/><path d="M24,-104 L24,-90 L38,-90" fill="none" stroke="#000" stroke-width="3"/>${l}`;
  } },
  coins: { h: 50, draw: () => [[-18, 0], [14, 0], [-2, -16]].map(([x, y]) =>
    `<ellipse ${W} cx="${x}" cy="${y - 12}" rx="17" ry="12" stroke-width="3.5"/><path d="M${x - 6},${y - 12} L${x + 6},${y - 12}" stroke="#000" stroke-width="3"/>`).join('') },
  food: { h: 40, draw: () =>
    `<path ${W} stroke-width="4" stroke-linejoin="round" d="M-26,0 L26,0 L26,-30 Z"/><circle cx="12" cy="-8" r="4"/><circle cx="-2" cy="-5" r="2.6"/><circle cx="18" cy="-19" r="2.4"/>` },
  fork: { h: 70, draw: () =>
    `<path d="M0,0 L0,-36 M-9,-36 L-9,-62 M0,-36 L0,-62 M9,-36 L9,-62 M-9,-36 L9,-36" fill="none" stroke="#000" stroke-width="6" stroke-linecap="round" stroke-linejoin="round"/>` },
  tool: { h: 100, draw: () =>
    `<path d="M0,0 L0,-70" stroke="#000" stroke-width="9" stroke-linecap="round"/><rect ${W} x="-34" y="-96" width="68" height="28" rx="4" stroke-width="4.5"/>` },
  lamp: { h: 150, draw: () =>
    `<path d="M0,0 L0,-70" stroke="#000" stroke-width="6"/><rect x="-22" y="-6" width="44" height="6"/><circle ${W} cx="0" cy="-100" r="30" stroke-width="5"/>` +
    `<path d="M0,-142 l0,-12 M40,-100 l12,0 M-40,-100 l-12,0 M29,-129 l9,-9 M-29,-129 l-9,-9" stroke="#000" stroke-width="4" stroke-linecap="round"/>` },
  box: { h: 86, draw: (o) =>
    `<rect ${W} x="-44" y="-78" width="88" height="78" rx="5" stroke-width="5"/><path d="M-44,-58 L44,-58" stroke="#000" stroke-width="3"/>${letter(o, -18, 34)}` },
  /* ---- the latent actors ---- */
  ghost: { h: 186, latent: true, draw: (o) =>
    `<path d="M-46,0 L-46,-116 C-46,-196 46,-196 46,-116 L46,0 L31,-15 L15,0 L0,-15 L-15,0 L-31,-15 Z" fill="#fff" stroke="#000" stroke-width="4" stroke-linejoin="round" stroke-dasharray="10 6"/>` +
    `<ellipse cx="-13" cy="-136" rx="5.5" ry="8"/><ellipse cx="15" cy="-136" rx="5.5" ry="8"/>` +
    `<text x="0" y="-60" text-anchor="middle" font-family="Impact,'Arial Narrow',sans-serif" font-size="${(o.mark || '').length > 1 ? 40 : 54}">${esc(o.mark || '?')}</text>` },
  guard: { h: 208, latent: true, draw: (o) => {
    const d = 'stroke-dasharray="9 6"';
    const sign = o.on
      ? `<path d="M58,-150 L86,-226" stroke="#000" stroke-width="5" stroke-linecap="round"/>` + noSign(92, -246, 30, true)
      : `<path d="M58,-104 L84,-150" stroke="#000" stroke-width="4" stroke-linecap="round" ${d}/>` + noSign(90, -168, 24, false);
    return `<polygon points="-28,-84 -40,0 -12,0 -3,-84" fill="#fff" stroke="#000" stroke-width="4" ${d}/><polygon points="3,-84 12,0 40,0 28,-84" fill="#fff" stroke="#000" stroke-width="4" ${d}/>` +
      `<polygon points="-42,-152 42,-152 27,-80 -27,-80" fill="#fff" stroke="#000" stroke-width="4" stroke-linejoin="round" ${d}/>` +
      `<path d="M-40,-146 L-66,-112 L-32,-92" fill="none" stroke="#000" stroke-width="4" stroke-linecap="round" stroke-linejoin="round" ${d}/>` +
      `<path d="M40,-146 L${o.on ? '62,-150' : '60,-106'}" fill="none" stroke="#000" stroke-width="4" stroke-linecap="round" ${d}/>` +
      `<path d="M-19,-186 C-19,-204 19,-204 19,-186 L16,-166 C10,-156 -10,-156 -16,-166 Z" fill="#fff" stroke="#000" stroke-width="4" stroke-linejoin="round" ${d}/>` +
      `<circle cx="-5" cy="-180" r="2.6"/><circle cx="9" cy="-180" r="2.6"/><path d="M-4,-167 L10,-167" stroke="#000" stroke-width="2.5"/>` +
      `<path d="M-24,-190 L-18,-208 L20,-208 L24,-190 Z"/><path d="M-26,-190 L34,-188" stroke="#000" stroke-width="5" stroke-linecap="round"/>` + sign;
  } },
};
/*  The figures a named thing of the program can be: the server offers the
 *  same list to the model (lps_story:story_figures/1). */
const figOf = (name) => (FIGS[name] && !FIGS[name].latent ? name : null);

const DEFS = `<svg width="0" height="0" style="position:absolute" aria-hidden="true"><defs>
  <filter id="cx-rough" x="-5%" y="-5%" width="110%" height="110%"><feTurbulence type="fractalNoise" baseFrequency="0.035" numOctaves="2" seed="7" result="n"/><feDisplacementMap in="SourceGraphic" in2="n" scale="4"/></filter>
  <filter id="cx-blur" x="-20%" y="-20%" width="140%" height="140%"><feGaussianBlur stdDeviation="3.2"/></filter>
  <pattern id="cx-dots2" width="10" height="10" patternUnits="userSpaceOnUse"><circle cx="2.5" cy="2.5" r="1.1"/><circle cx="7.5" cy="7.5" r="1.1"/></pattern>
  <pattern id="cx-dots3" width="6" height="6" patternUnits="userSpaceOnUse"><circle cx="3" cy="3" r="2.1"/></pattern>
</defs></svg>`;

/* ------------------------------------------------------------------ the cast */

/*  Who is in the story. A name of the program gets the figure the model chose,
 *  or a person when the name acts and a box when it does not. A latent actor
 *  gets its fixed figure, and the name the model gave it only when the reader
 *  asked for diverse actors. */
function buildCast(board, words, opts, clauseOf) {
  const named = [];
  board.names.forEach((n) => {
    const chosen = words?.cast?.[n.name]?.fig;
    if (chosen === 'none') return;
    const fig = figOf(chosen) || (n.acts > 0 ? 'person' : 'box');
    named.push({ id: n.name, name: n.name, fig, letter: n.name.charAt(0).toUpperCase(), acts: n.acts,
      is: n.acts > 0 ? 'acts in the run' : 'named in the run' });
  });
  named.slice(0, 10).forEach((c, i) => { c.tint = TINTS[i % TINTS.length]; });
  const latent = [];
  const diverse = opts.actors === 'diverse' ? (words?.latent || {}) : {};
  for (const l of board.latent) {
    const where = l.kind === 'law'
      ? (l.lines.length ? `the causal laws of ${l.lines.length > 1 ? 'lines' : 'line'} ${l.lines.map((x) => clauseOf(x).line).join(', ')}` : 'the causal laws')
      : `${l.kind === 'rule' ? 'the reactive rule' : 'the constraint'} of line ${clauseOf(l.line).line}`;
    if (l.kind === 'rule' && l.agent) continue;                 // the plan of a named agent: a thought of that agent
    const std = l.kind === 'law' ? 'The world' : l.kind === 'rule' ? `The rule of line ${clauseOf(l.line).line}` : `The guard of line ${clauseOf(l.line).line}`;
    latent.push({ id: l.id, kind: l.kind, line: l.line, lines: l.lines, acted: l.acted, watches: l.watches || [],
      fig: l.kind === 'constraint' ? 'guard' : 'ghost', mark: l.kind === 'law' ? '±' : 'IF',
      name: cap1(diverse[l.id] || std), is: where + (l.acted ? '' : ': it does nothing in this run') });
  }
  return { named, latent, byId: Object.fromEntries([...named, ...latent].map((c) => [c.id, c])) };
}

/* ---------------------------------------------------------------- one panel */

const functorOf = (term) => term.replace(/\(.*$/s, '').trim();

/*  Who stands in a panel, in order, and what each one says. Nothing here is
 *  a coordinate: a figure gets the next free place. */
function compose(panel, cast, board, opts, clauseOf, shownRules) {
  const figs = [], bals = [];
  const add = (c, extra = {}) => {
    if (!c) return null;
    let f = figs.find((x) => x.id === c.id);
    if (!f && figs.length < 7) { f = { ...c, ...extra }; figs.push(f); }
    return f;
  };
  const say = (who, kind, text, o = {}) => { if (who && text) bals.push({ who: who.id, kind, text, ...o }); };
  //  A figure stands in the same order in every panel: the order of the cast
  //  at the top of the strip, the named actors first and the latent ones
  //  after. A reader follows a character from panel to panel by its place.
  const rank = new Map([...cast.named, ...cast.latent].map((c, k) => [c.id, k]));
  const inOrder = () => figs.sort((x, y) => (rank.get(x.id) ?? 1e6) - (rank.get(y.id) ?? 1e6));
  const mono = !board.english;
  const rules = Object.fromEntries(board.latent.filter((l) => l.kind === 'rule').map((l) => [l.line, l]));

  if (panel.kind === 'start' || panel.kind === 'end') {
    const text = panel.holds.join(' ').toLowerCase();
    cast.named.filter((c) => new RegExp(`(^|[^a-z0-9_])${c.id.toLowerCase().replace(/[^a-z0-9_]/g, '.')}([^a-z0-9_]|$)`).test(text)).slice(0, 6).forEach((c) => add(c));
    if (!figs.length) cast.named.slice(0, 4).forEach((c) => add(c));
    inOrder();
    return { figs, bals };
  }
  if (panel.kind === 'silence') {
    for (const it of panel.items) {
      if (it.what === 'constraint') add(cast.byId['guard' + it.line], { blur: true });
      else if (it.what === 'rule') add(cast.byId['rule' + it.line], { blur: true });
    }
    inOrder();
    return { figs, bals };
  }

  //  The places go to the actors of the events first, then to the one who
  //  refuses and the ones refused, then to a rule with no agent (in the first
  //  panel in which the rule acts), and the things of the events have the rest.
  const byAgent = new Map();
  for (const e of panel.events) {
    const a = e.agent && cast.byId[e.agent] ? e.agent : null;
    if (a) { add(cast.byId[a]); if (!byAgent.has(a)) byAgent.set(a, []); byAgent.get(a).push(e); }
  }
  const refusedBy = new Map();
  for (const r of panel.refusals) {
    const g = add(cast.byId['guard' + r.line], { on: true });
    if (g) g.on = true;
    const a = r.agent && cast.byId[r.agent];
    if (a) { const f = add(a); if (f) f.refused = true; }
    const k = g ? g.id : '';
    if (!refusedBy.has(k)) refusedBy.set(k, []);
    refusedBy.get(k).push(r);
  }
  const ruleLines = [...new Set(panel.events.flatMap((e) => e.rules))];
  const ghosts = [];
  for (const line of ruleLines) {
    const r = rules[line];
    if (r && !r.agent && !shownRules.has(line)) { shownRules.add(line); const g = add(cast.byId['rule' + line]); if (g) ghosts.push([g, line]); }
  }
  for (const e of panel.events) for (const n of e.names) if (figs.length < 6) add(cast.byId[n]);
  const changes = panel.events.flatMap((e) => e.changes);
  const world = changes.length && figs.length < 6 ? add(cast.byId.world) : null;
  //  In the exploratory story, the constraints that watch an event of this
  //  panel and let it pass stand by.
  if (opts.mode === 'exploratory') {
    const fs = new Set(panel.events.map((e) => functorOf(e.term)));
    cast.latent.filter((l) => l.kind === 'constraint' && l.watches.some((w) => fs.has(w))).slice(0, 2)
      .forEach((l) => { if (figs.length < 6) add(l); });
  }

  // ---- what they say, the most important first; three balloons at most
  for (const [gid, rs] of refusedBy) {
    const g = figs.find((f) => f.id === gid);
    //  An action that the program tries again in the next cycle is refused
    //  again: the guard says each refused action once, and that covers every
    //  time it was refused in the panel.
    const texts = [...new Set(rs.map((r) => r.text))], shown = texts.slice(0, 2);
    const what = shown.join('; ') + (texts.length > 2 ? `; and ${texts.length - 2} more` : '');
    say(g, 'say', `NO: ${what}`, { mono, refusal: true, covers: rs.filter((r) => shown.includes(r.text)), ask: { term: rs[0].term, kind: 'refused', cycle: rs[0].cycle } });
  }
  for (const [a, es] of byAgent) {
    const what = es.slice(0, 2).map((e) => e.text).join('; ') + (es.length > 2 ? `; and ${es.length - 2} more` : '');
    say(figs.find((f) => f.id === a), 'say', mono ? what : cap1(what) + '.', { mono, event: true, covers: es.slice(0, 2), ask: { term: es[0].term, kind: 'event', cycle: es[0].cycle } });
  }
  for (const [g, line] of ghosts) say(g, 'think', clip(clauseOf(line).text, 190), { code: true });
  for (const [a, es] of byAgent) {
    for (const line of new Set(es.flatMap((e) => e.rules))) {
      const r = rules[line];
      if (r && r.agent === a && !shownRules.has(line)) { shownRules.add(line); say(figs.find((f) => f.id === a), 'think', clip(clauseOf(line).text, 190), { code: true }); }
    }
  }
  /*  What the causal laws think is the text of the law, as a rule's ghost
   *  thinks the text of its rule. The balloon used to list the fluents that
   *  started and ended, which the caption of the panel says already: two
   *  places for the same words. The law is what no other place of the panel
   *  shows. It is shown in the first panel in which it acts; a law of a
   *  library has no line in this document, and the ghost then stands silent. */
  if (world) {
    for (const line of new Set(changes.map((c) => c.line))) {
      const key = `law${line}`;
      if (!Number.isInteger(line) || shownRules.has(key)) continue;
      const text = clauseOf(line).text;
      if (!text) continue;
      shownRules.add(key);
      say(world, 'think', clip(text, 190), { code: true });
    }
  }
  //  One balloon for each speaker first, then the second thoughts.
  const seen = new Set(), first = [], rest = [];
  for (const b of bals) (seen.has(b.who) ? rest : (seen.add(b.who), first)).push(b);
  const kept = [...first, ...rest].slice(0, 3);
  inOrder();
  //  The events and the refusals that no balloon of the panel says: a panel
  //  has three balloons at most and a balloon two events at most, so a busy
  //  panel leaves some unsaid. The caption says those, and only those
  //  (panelHtml).
  const said = new Set(kept.flatMap((b) => b.covers || []));
  const unspoken = {
    events: panel.events.filter((e) => !said.has(e)),
    refusals: panel.refusals.filter((r) => !said.has(r)),
  };
  return { figs, bals: kept, unspoken };
}

const SW = 560, SH = 232, GROUND = SH - 26;

function stageSvg(figs, opts) {
  const n = figs.length || 1;
  const scale = [0.9, 0.9, 0.9, 0.8, 0.7, 0.62, 0.56, 0.5][Math.min(n, 7)];
  let draw = '', labels = '';
  figs.forEach((f, i) => {
    const F = FIGS[f.fig], s = scale * Math.min(1, 190 / F.h + 0.2), x = SW * (i + 0.5) / n - (f.fig === 'guard' ? 34 * s : 0);
    f.ax = x / SW; f.up = F.h * s + (f.fig === 'guard' && f.on ? 66 * s : 0) + 26;
    const tint = opts.colour && f.tint && !F.latent ? ` style="--fig:${f.tint}"` : '';
    let g = `<g transform="translate(${x.toFixed(1)},${GROUND}) scale(${s.toFixed(3)})"${tint}>${F.draw(f)}</g>`;
    if (f.refused) g += `<g transform="translate(${(x + 34 * s).toFixed(1)},${(GROUND - F.h * s - 4).toFixed(1)})">${noSign(0, 0, 13, true)}</g>`;
    draw += f.blur ? `<g filter="url(#cx-blur)" opacity=".6">${g}</g>` : g;
    const nm = clip(f.name.toUpperCase(), Math.max(6, Math.floor(52 / n)));
    labels += `<text x="${x.toFixed(1)}" y="${SH - 7}" text-anchor="middle" class="cx-lab" font-size="${n > 5 ? 12 : 14}">${esc(nm)}</text>`;
  });
  return `<svg class="cx-draw" viewBox="0 0 ${SW} ${SH}" preserveAspectRatio="xMidYMax meet">` +
    `<rect x="0" y="${GROUND}" width="${SW}" height="${SH - GROUND}" fill="url(#cx-dots2)"/><path d="M0,${GROUND} L${SW},${GROUND}" stroke="#000" stroke-width="4"/>` +
    `<g filter="url(#cx-rough)">${draw}</g>${labels}</svg>`;
}

function balloonsHtml(figs, bals) {
  const list = bals.map((b) => ({ b, f: figs.find((x) => x.id === b.who) })).filter((u) => u.f).sort((u, v) => u.f.ax - v.f.ax);
  let free = 1;
  for (const u of list) {
    u.wide = list.length === 1 ? 9 : list.length === 2 ? 6 : 4;
    u.c0 = Math.max(free, Math.min(13 - u.wide, Math.round(u.f.ax * 12 - u.wide / 2) + 1));
    free = u.c0 + u.wide;
  }
  for (let k = list.length - 1, lim = 13; k >= 0; k--) {
    if (list[k].c0 + list[k].wide > lim) list[k].c0 = Math.max(1, lim - list[k].wide);
    lim = list[k].c0;
  }
  return list.map(({ b, f, wide, c0 }) => {
    const js = list.length > 1 ? (f.ax < 0.5 ? 'start' : 'end') : f.ax < 0.36 ? 'start' : f.ax > 0.64 ? 'end' : 'center';
    const cls = ['cx-bal', b.kind === 'think' ? 'think' : '', b.code || b.mono ? 'code' : '', b.refusal ? 'refusal' : ''].join(' ');
    const ask = b.ask ? ` data-lps-term="${esc(b.ask.term)}" data-lps-kind="${b.ask.kind}" data-lps-cycle="${b.ask.cycle}"` : '';
    return `<div class="${cls}${b.ask ? ' askable' : ''}"${ask} data-ax="${f.ax.toFixed(4)}" data-up="${Math.round(f.up)}" data-kind="${b.kind}" style="grid-column:${c0}/span ${wide};justify-self:${js}">${esc(b.text)}</div>`;
  }).join('');
}

const tabText = (p) => (p.kind === 'silence' ? 'NOT IN THE RUN'
  : p.from === p.to ? `CYCLE ${p.from}` : p.to - p.from === 1 ? `CYCLE ${p.from} → ${p.to}` : `CYCLES ${p.from} TO ${p.to}`);

/*  The strip under a panel: the events as the engine recorded them, and the
 *  lines of the program that the panel comes from. A line is a link. */
function footHtml(panel, clauseOf) {
  const evs = (panel.events || []);
  const shown = evs.slice(0, 4).map((e) => `<span class="cx-ev askable" data-lps-term="${esc(e.term)}" data-lps-kind="event" data-lps-cycle="${e.cycle}"${e.kind === 'action' ? '' : ' data-observed="1"'}>${esc(e.term)}</span>`).join(' · ') +
    (evs.length > 4 ? ` · and ${evs.length - 4} more` : '');
  const refs = (panel.refusals || []).slice(0, 3).map((r) => `<span class="cx-ev cx-refused askable" data-lps-term="${esc(r.term)}" data-lps-kind="refused" data-lps-cycle="${r.cycle}">refused: ${esc(r.term)}</span>`).join(' · ');
  const lines = (label, ls) => {
    const u = [...new Set(ls.filter((l) => Number.isInteger(l)).map((l) => clauseOf(l).line))].sort((a, b) => a - b);
    return u.length ? `${label} ${u.map((l) => `<a class="cx-line" data-line="${l}" title="Show line ${l} in the editor">${l}</a>`).join(', ')}` : '';
  };
  const src = [
    lines('rule, line', evs.flatMap((e) => e.rules)),
    lines('causal law, line', evs.flatMap((e) => e.changes.map((c) => c.line))),
    lines('constraint, line', (panel.refusals || []).map((r) => r.line)),
    lines('line', (panel.items || []).map((i) => i.line)),
  ].filter(Boolean).join(' · ');
  const left = [shown, refs].filter(Boolean).join(' · ') || (panel.kind === 'beat' ? '' : 'no event');
  return `<div class="cx-ft"><code>${left}</code><i>${src}</i></div>`;
}

/*  `x` is for the exploratory story's "what if?" (renderComic): `whatIf`
 *  puts the control in the panel's head, `alt` says the panel is of the other
 *  run (nothing in it can be asked about: the questions go to the run of the
 *  editor), `tag` is a line that says how the panel differs. */
function panelHtml(panel, i, cast, board, words, opts, clauseOf, shownRules, x = {}) {
  const { figs, bals, unspoken } = compose(panel, cast, board, opts, clauseOf, shownRules);
  const svg = stageSvg(figs, opts);
  //  What did not happen is said by the program alone: a model that sums up
  //  "a rule never fired" as "no rule fired" says something false.
  /*  An event is said once. A figure says its event in a balloon, and the
   *  guard says what it refuses, so the computed caption keeps only what no
   *  balloon says: the fluents that started, ended or changed, and each event
   *  or refusal that no balloon of this panel says. A panel whose events change
   *  nothing then has no caption. A caption that a language model wrote is
   *  one piece of prose and is shown whole. */
  const parts = panel.caption_parts;
  const some = (texts, n) => texts.slice(0, n).join('; ') + (texts.length > n ? `; and ${texts.length - n} more` : '');
  const computed = parts && unspoken
    ? [unspoken.events.length ? cap1(some(unspoken.events.map((e) => e.text), 4)) + '.' : '',
       parts.effects,
       unspoken.refusals.length ? `Refused: ${some([...new Set(unspoken.refusals.map((r) => r.text))], 3)}.` : ''].filter(Boolean).join(' ')
    : panel.caption;
  const caption = (panel.kind !== 'silence' && words?.captions?.[i]) || computed;
  const sfxWord = panel.refusals?.length ? 'NO!' : (words?.sfx?.[i] || '');
  const sfx = sfxWord ? `<div class="cx-sfx${panel.refusals?.length ? ' refusal' : ''}">${esc(sfxWord)}</div>` : '';
  let extra = '';
  if (panel.kind === 'silence') {
    extra = '<ul class="cx-silence">' + panel.items.map((it) => {
      const l = it.line ? clauseOf(it.line) : null;
      return it.what === 'fluent' ? `<li>Nothing ends <b>${esc(it.text)}</b>: no causal law of the program can.</li>`
        : `<li>The ${it.what === 'rule' ? 'reactive rule' : 'constraint'} of <a class="cx-line" data-line="${l.line}">line ${l.line}</a> ${it.what === 'rule' ? 'never fired' : 'never refused anything'}: <span class="cx-clause">${esc(clip(l.text, 150))}</span></li>`;
    }).join('') + '</ul>';
  }
  if (panel.kind === 'end' && panel.outcome) extra = `<div class="cx-note${panel.outcome === 'failure' ? ' failure' : ''}">The run ends: ${esc(panel.outcome)}.</div>`;
  const quiet = panel.quiet_before > 0 ? `<span class="cx-quiet" title="cycles with no event before this panel">after ${panel.quiet_before} quiet cycle${panel.quiet_before > 1 ? 's' : ''}</span>` : '';
  const b = balloonsHtml(figs, bals);
  //  A right-click anywhere in a panel asks about the panel's refusal, or its
  //  first event; a balloon or a term of the strip below asks about its own.
  const r0 = panel.refusals?.[0], e0 = panel.events?.[0];
  const q = r0 ? { term: r0.term, kind: 'refused', cycle: r0.cycle } : e0 ? { term: e0.term, kind: 'event', cycle: e0.cycle } : null;
  const ask = q && !x.alt ? ` data-lps-term="${esc(q.term)}" data-lps-kind="${q.kind}" data-lps-cycle="${q.cycle}"` : '';
  const whatIf = x.whatIf ? `<button class="cx-whatif" data-panel="${i}" title="Tell the run again with a difference at this panel: an event that does not happen, or another event that happens">what if?</button>` : '';
  const tag = x.tag ? `<span class="cx-tag">${esc(x.tag)}</span>` : '';
  const title = x.alt ? 'A panel of the other run' : `Click to go to cycle ${panel.to}${q ? '. Right-click to ask why' : ''}`;
  return `<div class="cx-panel cx-${panel.kind}${q && !x.alt ? ' askable' : ''}${x.alt ? ' cx-alt' : ''}${x.tag ? ' cx-differs' : ''}"${ask} ${x.alt ? '' : `data-from="${panel.from}" data-to="${panel.to}" `}title="${title}">
    <div class="cx-hd"><div class="cx-num">${i + 1}</div><div class="cx-tab">${tabText(panel)}</div>${quiet}${tag}${whatIf}${caption ? `<div class="cx-capt">${esc(caption)}</div>` : ''}</div>
    ${b ? `<div class="cx-bals">${b}</div>` : ''}
    <div class="cx-stage${b ? ' has-bals' : ''}">${svg}${sfx}</div>${extra}
    ${footHtml(panel, clauseOf)}<svg class="cx-tails"></svg></div>`;
}

function castHtml(cast, opts) {
  const card = (c) => {
    const F = FIGS[c.fig], s = Math.min(1.1, 78 / F.h), w = c.fig === 'guard' ? 70 : ['fox', 'bird', 'animal', 'vehicle', 'boat', 'safe', 'machine', 'building'].includes(c.fig) ? 88 : 58;
    const tint = opts.colour && c.tint && !F.latent ? ` style="--fig:${c.tint}"` : '';
    const dx = c.fig === 'guard' ? -10 : c.fig === 'fox' ? 12 : 0;
    return `<div class="cx-card"><svg width="${w}" height="88" viewBox="0 0 ${w} 88"><g filter="url(#cx-rough)"><g transform="translate(${w / 2 + dx},${c.fig === 'guard' ? 87 : 84}) scale(${s.toFixed(3)})"${tint}>${F.draw(c)}</g></g></svg>` +
      `<div><b>${esc(c.name.toUpperCase())}</b><span>${esc(c.is)}</span></div></div>`;
  };
  return `<div class="cx-panel cx-cast"><div class="cx-grp"><h4>NAMED IN THE PROGRAM</h4><div class="cx-cards">${cast.named.map(card).join('') || '<span class="cx-none">no name</span>'}</div></div>` +
    (cast.latent.length ? `<div class="cx-grp lat"><h4>LATENT: BEHIND A RULE, A CAUSAL LAW OR A CONSTRAINT</h4><div class="cx-cards">${cast.latent.map(card).join('')}</div></div>` : '') +
    `<div class="cx-key"><b>HOW TO READ THE DRAWING.</b> Solid ink: an actor or a thing that the program names. A dashed outline: a latent actor, one that a reactive rule (IF), a causal law (±) or an integrity constraint (the sign) implies and the program does not name. Out of focus: something that the run does not contain. What a figure says is the event of the run, or the text of its rule. The strip under a panel gives the events and the lines of the program.</div></div>`;
}

/*  The run as the Timeline pane shows it, with the number of each panel over
 *  its cycles: the comic is a second reading of this picture, not another run. */
function ribbonHtml(board, tl, cast, opts) {
  const n = Math.max(1, tl.cycles), w = 1120, gut = 250, colw = (w - gut - 16) / n;
  const colX = (c) => gut + (c - 1) * colw;
  const lanes = (tl.fluents || []).slice(0, 14);
  const english = Object.fromEntries((tl.english || []).map((e) => [e.term, e.english]));
  const evCells = (tl.events || []).filter((c) => c.cycle >= 1), actions = Object.fromEntries((tl.actions || []).map((c) => [c.cycle, c.items]));
  const evRows = Math.min(4, Math.max(1, ...evCells.map((c) => c.items.length)));
  const stag = colw < 170, top = 78, rowH = 19, evTop = top + lanes.length * rowH + 16;
  const H = evTop + 14 + evRows * 14 * (stag ? 2 : 1) + 12;
  const tintOf = (term) => {
    if (!opts.colour) return null;
    const c = cast.named.find((x) => x.tint && new RegExp(`(^|[^A-Za-z0-9_])${x.id.replace(/[^A-Za-z0-9_]/g, '.')}([^A-Za-z0-9_]|$)`).test(term));
    return c ? c.tint : null;
  };
  let s = '';
  board.panels.forEach((p, i) => {
    if (p.kind === 'silence') return;
    const xa = colX(Math.max(1, p.from)) + colw / 2, xb = colX(Math.max(1, p.to)) + colw / 2, y = 13 + (i % 2) * 24;
    if (xb > xa) s += `<path d="M${xa},${y} L${xb},${y} M${xa},${y - 5} l0,10 M${xb},${y - 5} l0,10" stroke="#000" stroke-width="2.5"/>`;
    s += `<circle cx="${(xa + xb) / 2}" cy="${y}" r="10" fill="#fff" stroke="#000" stroke-width="2.5"/><text x="${(xa + xb) / 2}" y="${y + 5}" text-anchor="middle" class="cx-lab" font-size="13" stroke="none">${i + 1}</text>`;
  });
  const every = Math.ceil(n / 40);
  for (let c = 1; c <= n + 1; c++) if (n <= 60 || c === 1 || c === n + 1) s += `<path d="M${colX(c)},${top - 6} L${colX(c)},${evTop + 6}" stroke="#000" stroke-width="${c === 1 || c === n + 1 ? 2.5 : 1}"/>`;
  for (let c = 1; c <= n; c += every) s += `<text x="${colX(c) + colw / 2}" y="${top - 10}" text-anchor="middle" class="cx-lab" font-size="13" stroke="none">${c}</text>`;
  lanes.forEach((l, i) => {
    const y = top + i * rowH, t = tintOf(l.fluent);
    s += `<text x="${gut - 10}" y="${y + 13}" text-anchor="end" font-family="ui-monospace,Menlo,Consolas,monospace" font-weight="700" font-size="11.5"><title>${esc(english[l.fluent] || l.fluent)}</title>${esc(clip(l.fluent, 34))}</text>`;
    for (const iv of l.intervals) {
      const a = Math.max(1, iv.from), b = Math.max(a, iv.to);
      if (iv.to < 1) continue;
      s += `<rect x="${colX(a)}" y="${y + 3}" width="${(b - a + 1) * colw}" height="12" fill="${t || (i % 2 ? 'url(#cx-dots3)' : '#000')}" stroke="#000" stroke-width="1.5"/>`;
    }
  });
  s += `<text x="${gut - 10}" y="${evTop + 4}" text-anchor="end" font-family="ui-monospace,Menlo,Consolas,monospace" font-weight="700" font-size="11.5">events</text>`;
  const wide = n > 24;
  for (const cell of evCells) {
    const c = cell.cycle, x = colX(c), acts = actions[c] || [];
    s += `<circle cx="${x}" cy="${evTop}" r="${wide ? 4 : 6.5}" fill="${cell.items.every((e) => acts.includes(e)) ? '#000' : '#fff'}" stroke="#000" stroke-width="2.5"><title>${esc(cell.items.join(', '))}</title></circle>`;
    if (wide) continue;
    cell.items.slice(0, evRows).forEach((e, k) => {
      const more = k === evRows - 1 && cell.items.length > evRows, label = more ? `+${cell.items.length - k} more` : e;
      const y = evTop + 22 + (k + (stag && c % 2 ? evRows : 0)) * 14, half = label.length * 3.1, tx = Math.max(half + 4, Math.min(w - half - 4, x));
      s += `<text x="${tx}" y="${y}" text-anchor="middle" font-family="ui-monospace,Menlo,Consolas,monospace" font-weight="${acts.includes(e) ? 700 : 400}" font-size="10.3">${esc(label)}</text>`;
    });
    if (stag && c % 2) s += `<path d="M${x},${evTop + 8} L${x},${evTop + 12 + evRows * 14}" stroke="#000" stroke-width="1" stroke-dasharray="2 3"/>`;
  }
  //  What a constraint refused, an event from outside or an action of the
  //  program: a cross above the line of the events, at its cycle.
  const crossed = new Map();
  for (const r of [...(tl.refused || []), ...(tl.blocked || [])]) {
    if (r.cycle < 1 || r.cycle > n) continue;
    if (!crossed.has(r.cycle)) crossed.set(r.cycle, []);
    crossed.get(r.cycle).push(...r.items);
  }
  for (const [c, items] of crossed) {
    const x = colX(c), y = evTop - 11, k = wide ? 2.5 : 3.5;
    s += `<g stroke="${opts.colour ? 'var(--cx-red)' : '#000'}" stroke-width="2.5" stroke-linecap="round"><title>${esc('refused by a constraint: ' + [...new Set(items)].join(', '))}</title><path d="M${x - k},${y - k} L${x + k},${y + k} M${x + k},${y - k} L${x - k},${y + k}"/></g>`;
  }
  return `<div class="cx-panel cx-ribbon"><div class="cx-hd"><div class="cx-tab">THE SAME RUN, AS THE TIMELINE SHOWS IT</div>
    <div class="cx-capt plain">A column is a cycle. A bar is a fluent that holds. A dot on a line is an event; a black dot and bold letters, an action of the program. ${crossed.size ? 'A cross is an event or an action that a constraint refused. ' : ''}A number in a circle is a panel above.</div></div>
    <svg viewBox="0 0 ${w} ${H}" style="display:block;width:100%">${s}</svg></div>`;
}

/*  After the layout: a tail from each balloon towards the head of its speaker. */
function drawTails(root) {
  for (const panel of root.querySelectorAll('.cx-panel')) {
    const svg = panel.querySelector('.cx-tails'), stage = panel.querySelector('.cx-stage'), draw = panel.querySelector('.cx-draw');
    if (!svg || !stage || !draw) continue;
    svg.replaceChildren();
    const P = panel.getBoundingClientRect(), D = draw.getBoundingClientRect();
    if (!D.width) continue;
    const k = Math.min(D.width / SW, D.height / SH), ox = D.left + (D.width - SW * k) / 2 - P.left, oy = D.bottom - P.top;
    const bw = panel.clientLeft || 0;
    const add = (tag, attrs) => { const e = document.createElementNS(NS, tag); for (const a in attrs) e.setAttribute(a, attrs[a]); svg.appendChild(e); };
    for (const bal of panel.querySelectorAll('.cx-bal')) {
      const B = bal.getBoundingClientRect();
      const tx = ox - bw + Number(bal.dataset.ax) * SW * k, ty = oy - bw - Number(bal.dataset.up) * k + 16 * k;
      const by = B.bottom - P.top - bw - 4, bx = Math.max(B.left - P.left - bw + 30, Math.min(B.right - P.left - bw - 30, tx));
      const ey = Math.max(by + 10, by + (ty - by) * 0.9), ex = bx + (tx - bx) * 0.9;
      if (bal.dataset.kind === 'think') {
        const m = Math.max(2, Math.round((ey - by) / 24));
        for (let j = 0; j < m; j++) { const f = (j + 0.4) / m; add('circle', { cx: bx + (ex - bx) * f, cy: by + 8 + (ey - by - 8) * f, r: 7.5 - 4.5 * f, fill: '#fff', stroke: '#000', 'stroke-width': 2.5 }); }
      } else {
        add('polygon', { points: `${bx - 12},${by} ${ex},${ey} ${bx + 12},${by}`, fill: '#fff' });
        add('path', { d: `M${bx - 12},${by + 2} Q${bx - 4},${(by + ey) / 2} ${ex},${ey} Q${bx + 7},${(by + ey) / 2} ${bx + 12},${by + 2}`, fill: '#fff', stroke: '#000', 'stroke-width': 2.5, 'stroke-linejoin': 'round' });
        add('path', { d: `M${bx - 10},${by} L${bx + 10},${by}`, stroke: '#fff', 'stroke-width': 6 });
      }
    }
  }
}

/* ----------------------------------------------------------------- the pane */

/**
 * Draw the strip into `pane`.
 *   data.board     the `story` reply
 *   data.words     the `story_words` reply's `words`, or null (computed captions)
 *   data.timeline  the `timeline` reply
 *   data.status    one line about where the words come from
 *   opts           { mode, actors, colour, cycle, name }
 *   hooks          { onSeek(cycle), goToLine(line), clauseOf(line) -> {line, text} }
 */
export function renderComic(pane, data, opts, hooks) {
  const { board, words, timeline } = data;
  const clauseOf = hooks.clauseOf;
  const cast = buildCast(board, words, opts, clauseOf);
  const shownRules = new Set();
  const title = (words?.title || (opts.name || 'the run').replace(/\.[a-z]+$/i, '').replace(/[_-]+/g, ' ')).toUpperCase();
  /*  The exploratory story asks "what if?" of a panel: the same program run
   *  again from the start with one difference at that panel's cycle (the
   *  `story_what_if` operation). The two runs are the same up to the first
   *  panel that differs, so the strip is as it was down to there, and two
   *  columns from there on: the run of the editor on the left, the other run on the
   *  right, a panel of one beside the panel with the same number of the
   *  other. A panel that one run has and the other has not says so. */
  const canAsk = (p) => board.mode === 'exploratory' && hooks.onWhatIf && (p.kind === 'beat' || p.kind === 'start');
  const one = (p, i) => panelHtml(p, i, cast, board, words, opts, clauseOf, shownRules, { whatIf: canAsk(p) });
  let panels;
  const alt = data.alt;
  if (!alt) panels = `<div class="cx-grid">${board.panels.map(one).join('')}</div>`;
  else {
    const sig = (p) => JSON.stringify([p.kind, p.from, p.to, p.caption, (p.events || []).map((e) => e.term), (p.refusals || []).map((r) => r.term), p.holds || [], p.outcome || '']);
    const mine = board.panels.map(sig), theirs = alt.board.panels.map(sig);
    let d = 0;
    while (d < mine.length && d < theirs.length && mine[d] === theirs[d]) d++;
    const altCast = buildCast(alt.board, null, opts, clauseOf), altRules = new Set(shownRules);
    const said = [
      alt.removed.length ? `${alt.removed.map((t) => `“${t}”`).join(' and ')} ${alt.removed.length > 1 ? 'do' : 'does'} not happen` : '',
      alt.added.length ? `${alt.added.map((t) => `“${t}”`).join(' and ')} ${alt.added.length > 1 ? 'happen' : 'happens'}` : '',
    ].filter(Boolean).join(', and ');
    const same = d === mine.length && d === theirs.length;
    //  The panels that the two runs share are drawn as they were before the
    //  question: in the same grid, as many columns as the pane has room for.
    //  Only the part where the runs differ is two columns, one for each run.
    let h = d ? `<div class="cx-grid">${board.panels.slice(0, d).map(one).join('')}</div>` : '';
    h += `<div class="cx-panel cx-fork"><div class="cx-hd"><div class="cx-tab">WHAT IF, AT CYCLE ${alt.cycle}</div>
      <div class="cx-capt plain">${esc(cap1(said))}. ${same ? 'The other run is the same as this run, panel for panel.' : `The two runs are the same before panel ${d + 1}. From there, the run of the editor is on the left and the other run is on the right.`}</div>
      <button class="cx-whatif-close" title="Go back to the one run">close the what if</button></div></div>`;
    if (!same) {
      h += '<div class="cx-grid cx-two"><div class="cx-col-hd">THE RUN</div><div class="cx-col-hd">WHAT IF</div>';
      const n = Math.max(mine.length, theirs.length);
      for (let i = d; i < n; i++) {
        const a = board.panels[i], b = alt.board.panels[i];
        h += a ? panelHtml(a, i, cast, board, words, opts, clauseOf, shownRules, { whatIf: canAsk(a), tag: theirs.includes(mine[i]) ? '' : 'only in the run' }) : '<div class="cx-gap"></div>';
        h += b ? panelHtml(b, i, altCast, alt.board, null, opts, clauseOf, altRules, { alt: true, tag: mine.includes(theirs[i]) ? '' : 'only in the what if' }) : '<div class="cx-gap"></div>';
      }
      h += '</div>';
    }
    panels = h;
  }
  const root = document.createElement('div');
  root.className = 'comic' + (opts.colour ? ' colour' : '');
  root.innerHTML = `${DEFS}<div class="cx-page">
    <div class="cx-ep">${esc(title)}<small>${esc(opts.name || '')}${board.mode === 'exploratory' ? ' · exploratory' : ''}</small></div>
    ${castHtml(cast, opts)}
    ${panels}
    ${timeline ? ribbonHtml(board, timeline, cast, opts) : ''}
    <div class="cx-folio">${esc(data.status || '')}</div></div>`;
  pane.replaceChildren(root);
  root.addEventListener('click', (e) => {
    const line = e.target.closest('.cx-line');
    if (line) { hooks.goToLine(Number(line.dataset.line)); e.stopPropagation(); return; }
    const wi = e.target.closest('.cx-whatif');
    if (wi) { hooks.onWhatIf(board.panels[Number(wi.dataset.panel)]); e.stopPropagation(); return; }
    if (e.target.closest('.cx-whatif-close')) { hooks.onCloseWhatIf(); e.stopPropagation(); return; }
    const p = e.target.closest('.cx-panel[data-to]');
    if (p) hooks.onSeek(Number(p.dataset.to));
  });
  for (const n of root.querySelectorAll('.askable')) askable(n, { term: n.dataset.lpsTerm, kind: n.dataset.lpsKind, cycle: Number(n.dataset.lpsCycle) });
  const tails = () => drawTails(root);
  requestAnimationFrame(tails);
  if (window.ResizeObserver) { const ro = new ResizeObserver(tails); ro.observe(root); }
  markCycle(pane, opts.cycle);
}

/** Mark the panel that tells the cycle on the slider. */
export function markCycle(pane, cycle) {
  let best = null;
  for (const p of pane.querySelectorAll('.cx-panel[data-to]')) {
    p.classList.remove('now');
    if (p.classList.contains('cx-silence')) continue;
    const from = Number(p.dataset.from), to = Number(p.dataset.to);
    if (!best && (cycle <= to && (cycle > from || from === to || cycle <= 1))) best = p;
  }
  if (best) best.classList.add('now');
}

/* le-words.js — a term in the program's own English.
 *
 * A Logical English document says, in as many words, what its predicates mean:
 *
 *     *an object* is at *a place*; known as loc.
 *     *a payer* transfers *an amount* to *a payee*; known as transfer.
 *
 * and then every picture of it used to be captioned in the internal syntax —
 * `loc(goat,north)`, `transfer(fariba,10,bob)`, a legend reading `loc`,
 * `makeLoc`, `dealWithGoat`. For a language whose whole promise is that the
 * program is a text a domain expert can read, that is the promise withdrawn at
 * the last moment (the review's R5). The mapping was in the buffer all along.
 *
 * So: one reader over the template declarations, and the panes say the terms
 * the way the document says them. It is a *fallback* mechanism — a term with no
 * template, or one whose arity does not match, is printed as it always was, and
 * a program that is not Logical English has no templates at all and nothing
 * changes for it.
 *
 * Nothing here talks to the server. The templates are in the text.
 */

//  "name/arity" → { parts, slots }: the words around the holes, and the holes.
let table = new Map();

/**
 * Read the templates of a Logical English document. Anything else — an LPS
 * program, an empty buffer — clears them, because saying one program's terms
 * in another's words is worse than saying them plainly.
 */
export function setTemplates(text) {
  table = parse(text);
  return table.size;
}

export const haveTemplates = () => table.size > 0;

/*  The template declarations, wherever they are in the document.
 *
 *  A template is a line with holes in it: `*a payer* transfers *an amount*`.
 *  What predicate it names is either said (`; known as transfer`) or derived
 *  the way LE2 derives it — the words that are not holes, joined with
 *  underscores (le_grammar.pl, extract_functor/2). Both are read here, so a
 *  document that names none of its predicates is understood as well as one
 *  that names all of them.
 */
function parse(text) {
  const m = new Map();
  if (!text) return m;
  for (const raw of String(text).split('\n')) {
    const line = raw.trim();
    if (!line.includes('*')) continue;
    if (line.startsWith('%')) continue;
    let body = line.replace(/[.;,]\s*$/, '').trim();
    let name = null;
    const known = body.match(/;\s*known as\s+([^\s.;]+)\s*$/i);
    if (known) { name = known[1]; body = body.slice(0, known.index).trim(); }
    const parts = [], slots = [];
    const hole = /\*([^*]*)\*/g;
    let last = 0, mm;
    while ((mm = hole.exec(body))) {
      parts.push(body.slice(last, mm.index));
      slots.push(mm[1]);
      last = hole.lastIndex;
    }
    if (!slots.length) continue;
    parts.push(body.slice(last));
    if (!name) name = parts.join(' ').split(/\s+/).filter(Boolean).join('_');
    const key = `${name}/${slots.length}`;
    if (!m.has(key)) m.set(key, { parts, slots });
  }
  return m;
}

/**
 * A term, said in the document's words: `loc(goat,north)` → "goat is at north".
 * The term itself when there is no template for it — which is most programs,
 * and every program before this.
 */
export function sayTerm(term) {
  const s = String(term == null ? '' : term).trim();
  if (!s || !table.size) return s;
  const { name, args } = splitTerm(s);
  const t = table.get(`${name}/${args.length}`);
  if (!t) return s;
  //  An argument may be a term with words of its own.
  const said = args.map((a) => (a.includes('(') ? sayTerm(a) : unquote(a)));
  let out = '';
  t.parts.forEach((p, i) => { out += p + (i < said.length ? ' ' + said[i] + ' ' : ''); });
  return out.replace(/\s+/g, ' ').trim() || s;
}

/**
 * A predicate's name in the document's words — the template with its holes
 * taken out, for a legend or a column head: `loc` → "is at". The name itself
 * when there is no template, whatever its arity.
 */
export function sayPredicate(name) {
  const n = String(name || '').trim();
  if (!n || !table.size) return n;
  for (const [key, t] of table) {
    if (key.slice(0, key.lastIndexOf('/')) !== n) continue;
    //  `the balance of … is`, rather than the words run together: the holes
    //  are part of what the predicate says.
    const words = t.parts.map((x) => x.trim()).filter(Boolean).join(' … ');
    return words || n;
  }
  return n;
}

/*  A term as its functor and its arguments, as text. Not a Prolog reader: it
    has to survive quoted atoms and nested terms and say something sensible
    about anything else, because what arrives is whatever the program's terms
    print as. */
function splitTerm(s) {
  const i = s.indexOf('(');
  if (i < 0 || !s.endsWith(')')) return { name: s, args: [] };
  const name = s.slice(0, i).trim();
  const inner = s.slice(i + 1, -1);
  const args = [];
  let depth = 0, cur = '', quote = null;
  for (const ch of inner) {
    if (quote) { cur += ch; if (ch === quote) quote = null; continue; }
    if (ch === "'" || ch === '"') { quote = ch; cur += ch; continue; }
    if (ch === '(' || ch === '[' || ch === '{') depth++;
    else if (ch === ')' || ch === ']' || ch === '}') depth--;
    if (ch === ',' && depth === 0) { args.push(cur.trim()); cur = ''; continue; }
    cur += ch;
  }
  if (cur.trim() !== '') args.push(cur.trim());
  return { name, args };
}

//  `'John Smith'` is the atom John Smith, and the quotes are Prolog's.
const unquote = (a) => (a.length > 1 && a[0] === "'" && a.endsWith("'") ? a.slice(1, -1) : a);

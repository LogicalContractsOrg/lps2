/* doc-for-this.js — "Documentation for this" (the editor's context menu).
 *
 * The documentation about what is under the cursor, found by the
 * documentation's search (static/docs-extras.js, /docs/search). What is
 * searched for depends on the token's *class*, not only its text: a variable
 * `X` is looked up as "variables", a date as "dates", `initiates` as that
 * word, a name the program declares as a fluent as "fluents". The token itself
 * is offered as a search of its own on the results page. LE2's editor has the
 * same action (editor/src/doc-for-this.ts).
 */
import * as monaco from '../node_modules/monaco-editor/esm/vs/editor/editor.api.js';
import { LANGUAGE_ID, vocabulary } from './lps-language.js';

//  [token type, search, what it is], for both grammars (lps-language.js, le-language.js).
const CONCEPTS = [
  [/^comment/, 'comments', 'a comment'],
  [/^string/, 'strings', 'a string'],
  [/^number\.date/, 'dates', 'a date'],
  [/^number/, 'numbers', 'a number'],
  [/^variable/, 'variables', 'a variable'],
  [/^operator/, 'operators', 'an operator'],
];

function tokenAt(model, lineNo, column, languageId) {
  const first = Math.max(1, lineNo - 400);
  const lines = [];
  for (let i = first; i <= lineNo; i++) lines.push(model.getLineContent(i));
  let tokens = [];
  try { tokens = monaco.editor.tokenize(lines.join('\n'), languageId)[lines.length - 1] || []; } catch { /* none */ }
  const text = lines[lines.length - 1];
  let found = null;
  for (let i = 0; i < tokens.length; i++) {
    const start = tokens[i].offset;
    const end = i + 1 < tokens.length ? tokens[i + 1].offset : text.length;
    if (column - 1 >= start && column - 1 <= end) {
      const t = text.slice(start, end);
      if (t.trim() === '') continue;
      found = { type: String(tokens[i].type).replace(new RegExp(`\\.${languageId}$`), ''), text: t.trim() };
      if (column - 1 < end) break;
    }
  }
  return found;
}

/** {q, about, word} for the cursor or selection of `ed`, or null. */
export function docQueryAt(ed) {
  const model = ed.getModel(), sel = ed.getSelection(), pos = ed.getPosition();
  const languageId = model.getLanguageId();
  const selected = sel && !sel.isEmpty() ? model.getValueInRange(sel).trim() : '';
  const lineNo = selected ? sel.startLineNumber : pos.lineNumber;
  const column = selected ? sel.startColumn : pos.column;
  const token = tokenAt(model, lineNo, column, languageId);
  if (selected && (!token || selected.length > token.text.length || !token.text.includes(selected))) {
    return { q: `"${selected.replace(/"/g, '')}"`, about: `Documentation for “${selected}”`, word: selected };
  }
  if (!token || !token.text) {
    const w = model.getWordAtPosition(pos)?.word;
    return w ? { q: w, about: `Documentation for “${w}”`, word: w } : null;
  }
  const word = selected
    || (/^comment/.test(token.type) ? token.text.replace(/^%\s*/, '').slice(0, 40)
                                    : token.text.replace(/[:.]$/, '').replace(/^\*|\*$/g, ''));
  for (const [re, q, what] of CONCEPTS) {
    if (re.test(token.type)) return { q, about: `Documentation for “${word}”, ${what}`, word };
  }
  if (languageId === LANGUAGE_ID && token.type === 'identifier') {
    //  A name of the program's: what it declares it as.
    const v = vocabulary();
    for (const [kind, what] of [['fluents', 'a fluent'], ['events', 'an event'], ['actions', 'an action']]) {
      if (v[kind].includes(word)) return { q: kind, about: `Documentation for “${word}”, ${what} of this program`, word };
    }
    return { q: 'predicates', about: `Documentation for “${word}”, a predicate`, word };
  }
  if (/^(keyword|type|predefined)/.test(token.type)) {
    return { q: `"${word}"`, about: `Documentation for “${word}”, ${token.type === 'predefined' ? 'a system predicate' : 'a keyword'}`, word };
  }
  if (languageId !== LANGUAGE_ID) {
    //  A word of a Logical English sentence: a word of one of its templates.
    return { q: 'templates', about: `Documentation for “${word}”, a word of a template`, word };
  }
  return { q: word, about: `Documentation for “${word}”`, word };
}

export function openDocQuery(query) {
  const p = new URLSearchParams(query);
  window.open(`/docs/search?${p.toString()}`, '_blank', 'noopener');
}

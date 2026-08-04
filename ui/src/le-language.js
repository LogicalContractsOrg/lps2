/* le-language.js — Logical English in Monaco, built from LE2's own lexicon.
 *
 * The keywords are *not* copied into this repository. LE2 generates them from
 * `i18n/keywords.csv` into 6,800 lines of TypeScript for its own editor; a
 * second copy here would turn a documentation-duplication discipline into a
 * code-duplication problem, and it would be wrong for every language but
 * English within a release. So the mode is built at run time from what the
 * server answers to `le_lexicon` — which is that same CSV, read once.
 *
 * The tokenizer is deliberately simple. Logical English is prose: what a
 * reader needs marked is the section openers, the connectives, the *slots*,
 * and the comments. Everything else is words.
 */
export const LE_LANGUAGE_ID = 'logicalenglish';

let built = false;

/** Build the mode from a lexicon reply. Safe to call again — a second call
 *  with a different language rebuilds the tokenizer in place. */
export function registerLe(monaco, lexicon) {
  if (!built) {
    monaco.languages.register({ id: LE_LANGUAGE_ID, extensions: ['.le'] });
    monaco.languages.setLanguageConfiguration(LE_LANGUAGE_ID, {
      comments: { lineComment: '%' },
      brackets: [['(', ')'], ['[', ']']],
      autoClosingPairs: [
        { open: '(', close: ')' }, { open: '[', close: ']' },
        { open: '*', close: '*' },
      ],
      wordPattern: /[A-Za-z][A-Za-z0-9_-]*/,
    });
    built = true;
  }
  monaco.languages.setMonarchTokensProvider(LE_LANGUAGE_ID, monarch(lexicon));
}

/*  Section openers first, then connectives, then everything a phrase can be.
 *  Order matters in Monarch: the first rule that matches wins, and "the
 *  fluents are" must beat the article "the". */
function monarch(lex) {
  const byCategory = (want) => Object.entries(lex?.categories || {})
    .filter(([, c]) => c === want)
    .flatMap(([key]) => (lex.keywords[key] || []).map((words) => words.join(' ')))
    .filter(Boolean)
    //  Longest first: `the actions are` must be tried before `the`.
    .sort((a, b) => b.length - a.length);

  const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+');
  const alt = (list) => (list.length ? new RegExp(`(?:${list.map(escape).join('|')})\\b`) : null);

  const sections = alt(byCategory('section'));
  const connectives = alt(byCategory('connective'));
  const rules = [];
  rules.push([/%.*$/, 'comment']);
  //  A slot: `*a person*`, which is where the variables live.
  rules.push([/\*[^*]+\*/, 'variable']);
  rules.push([/"[^"]*"/, 'string']);
  rules.push([/\b\d[\d.,]*\b/, 'number']);
  if (sections) rules.push([sections, 'keyword.declaration']);
  if (connectives) rules.push([connectives, 'keyword']);
  rules.push([/[:.]/, 'delimiter']);
  return { ignoreCase: true, defaultToken: '', tokenizer: { root: rules } };
}

/*  Completion from the program's own templates. Role-aware: a template that
 *  declares a fluent and one that declares an action look identical as text,
 *  and which is which is the first thing an author needs to know. */
export function templateCompletions(monaco, templates) {
  const K = monaco.languages.CompletionItemKind;
  const kind = { fluent: K.Field, event: K.Event, action: K.Method,
    prolog_event: K.Event, timeless: K.Constant };
  return (templates || []).map((t) => ({
    label: t.surface,
    kind: kind[t.role] || K.Text,
    detail: `${t.role} — ${t.functor}/${t.arity}`,
    //  The slots come back as `*a person*`; make them tab stops.
    insertText: slotsToSnippet(t.surface),
    insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet,
    documentation: t.flags?.length ? t.flags.join(', ') : undefined,
  }));
}

function slotsToSnippet(surface) {
  let i = 0;
  return String(surface).replace(/\*([^*]+)\*/g, (_, inner) => `\${${++i}:${inner}}`);
}

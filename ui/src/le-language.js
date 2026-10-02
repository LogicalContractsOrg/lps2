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

/*  Which keys of the lexicon are marked, and how. The keys are chosen one by
 *  one, as LE2's own editor chooses them (its editor/src/le-language.ts), and
 *  not by category: the `section` category also holds LE2's internal pieces
 *  -- `marker_is` is the bare word "is", `reserved_word` the bare words
 *  "contract", "events" and so on, `guard` the first words of every header --
 *  and marking those coloured every "is" and every "contract" in a program.  */
const HEADERS = [            // a section's opening words, at the start of a line
  'meta_target', 'kb_open', 'ontology', 'constants', 'predicates', 'templates',
  'functions', 'fluents', 'events', 'actions', 'prolog_events', 'annexes',
  'resources_include', 'services_include', 'kb_include', 'kb_extends',
  'provenance_required', 'scenario', 'query',
  'lps_max_time', 'lps_max_real_time', 'lps_min_cycle_time',
];
const KEYWORDS = [           // the words that join sentences, anywhere in a line
  'if', 'only_if', 'unless', 'and_unless', 'either', 'any_of', 'all_of',
  'at_least_one_of', 'otherwise', 'it_the_case', 'not_the_case', 'forall',
  'expects', 'known_as', 'flip_query',
  'lps_when', 'lps_then', 'lps_if', 'lps_initially', 'lps_must_not', 'lps_goal',
  'lps_initiate', 'lps_terminate', 'lps_becomes',
  'lps_this_law_replaces', 'lps_this_constraint_replaces',
];
const LINE_START = ['and', 'or']; // "and" and "or" only where they open a condition

/*  Order matters in Monarch: the first rule that matches wins, so the longer
 *  phrases come first, and a word that matches nothing is taken whole, so
 *  that "and" is never found inside "standard".  */
function monarch(lex) {
  const phrases = (keys) => keys
    .flatMap((key) => (lex?.keywords?.[key] || []).map((words) => words.join(' ')))
    .filter(Boolean)
    //  Longest first: `the actions are` must be tried before `the`.
    .sort((a, b) => b.length - a.length);

  const W = '[A-Za-zÀ-ÖØ-öø-ÿ0-9_]';
  const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace(/\s+/g, '\\s+');
  const alt = (list) => list.map(escape).join('|');
  const whole = (list) => (list.length ? `(?<!${W})(?:${alt(list)})(?!${W})` : null);

  const headers = whole(phrases(HEADERS));
  const contractOpen = phrases(['contract_open']), contractStates = phrases(['contract_states']);
  const keywords = whole(phrases(KEYWORDS));
  const lineStart = whole(phrases(LINE_START));
  const rules = [];
  rules.push([/%.*$/, 'comment']);
  //  A slot: `*a person*`, which is where the variables live.
  rules.push([/\*[^*]+\*/, 'variable']);
  rules.push([/"[^"]*"/, 'string']);
  rules.push([new RegExp(`\\d[\\d.,]*(?!${W})`), 'number']);
  if (headers) rules.push([new RegExp(`^\\s*${headers}`), 'keyword.declaration']);
  //  "the contract <name> states that:" -- the opening words only on such a line.
  if (contractOpen.length && contractStates.length) {
    rules.push([new RegExp(`^\\s*(?:${alt(contractOpen)})(?=\\s.*\\s(?:${alt(contractStates)})\\s*:)`),
      'keyword.declaration']);
    rules.push([new RegExp(`(?<!${W})(?:${alt(contractStates)})(?=\\s*:)`), 'keyword.declaration']);
  }
  if (lineStart) rules.push([new RegExp(`^\\s*${lineStart}`), 'keyword']);
  if (keywords) rules.push([new RegExp(keywords), 'keyword']);
  rules.push([new RegExp(`${W}+(?:'${W}*)?`), '']);
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

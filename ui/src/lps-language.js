/* lps-language.js — one Monarch grammar for LPS *and* Prolog.
 *
 * §I.10.1a: an LPS program is a Prolog file. An LPS construct and a helper
 * clause sit in the same buffer, and a grammar that only knows one of them
 * mis-colours the other — which is why this is one language rather than two.
 *
 * The keyword lists come from tools/gen_monarch.pl, which reads
 * src/core/lps_ops.pl. Editing them here would be editing a copy.
 */
import { operators, declarations, internals, systemPredicates, operatorTable }
  from './generated/lps-vocabulary.js';

export const LANGUAGE_ID = 'lps';

/*  What *this* program declares, as opposed to what the language has. Filled
 *  in from the server's analyse profile after every compile, so completion
 *  offers `temperature(_)` in the thermostat and `row(_,_)` in the goat. */
let PROGRAM_EVENTS = [];
let PROGRAM_ACTIONS = [];
export function setVocabulary(profile) {
  PROGRAM_EVENTS = profile?.events || [];
  PROGRAM_ACTIONS = profile?.actions || [];
}

export const languageConfiguration = {
  comments: { lineComment: '%', blockComment: ['/*', '*/'] },
  brackets: [['(', ')'], ['[', ']'], ['{', '}']],
  autoClosingPairs: [
    { open: '(', close: ')' }, { open: '[', close: ']' }, { open: '{', close: '}' },
    { open: "'", close: "'", notIn: ['string', 'comment'] },
    { open: '"', close: '"', notIn: ['string', 'comment'] },
  ],
  surroundingPairs: [['(', ')'], ['[', ']'], ['{', '}'], ["'", "'"], ['"', '"']],
  /* A clause ends at `.` followed by whitespace, and folding by clause is the
   * only structure an LPS file really has. */
  folding: { markers: { start: /^\s*\/\*/, end: /\*\/\s*$/ } },
};

export const monarchTokens = {
  defaultToken: '',
  ignoreCase: false,
  operators,
  declarations,
  internals,
  systemPredicates,

  symbols: /[=><!~?:&|+\-*\/^@#$\\]+/,

  tokenizer: {
    root: [
      [/%.*$/, 'comment'],
      [/\/\*/, 'comment', '@comment'],

      // 0'c character codes, 0x/0o/0b radix, floats, integers
      [/0'(\\.|.)/, 'number'],
      [/0[xX][0-9a-fA-F]+/, 'number.hex'],
      [/0[oO][0-7]+/, 'number.octal'],
      [/0[bB][01]+/, 'number.binary'],
      [/\d+\.\d+([eE][-+]?\d+)?/, 'number.float'],
      [/\d+/, 'number'],

      // dates, which the contract corpus is full of
      [/\d{4}-\d{2}-\d{2}/, 'number.date'],

      [/'(?:[^'\\]|\\.|'')*'/, 'string.quoted'],   // quoted atom
      [/"(?:[^"\\]|\\.)*"/, 'string'],
      [/`(?:[^`\\]|\\.)*`/, 'string.backquoted'],

      // variables: _Foo, Foo, and the anonymous _
      [/\b_[A-Za-z0-9_]*\b/, 'variable'],
      [/\b[A-Z][A-Za-z0-9_]*\b/, 'variable'],

      // words, classified against the generated vocabulary
      [/[a-z][A-Za-z0-9_]*/, {
        cases: {
          '@operators': 'keyword',
          '@declarations': 'keyword.declaration',
          '@internals': 'type',
          '@systemPredicates': 'predefined',
          '@default': 'identifier',
        },
      }],

      [/[()\[\]{}]/, '@brackets'],
      [/[,.|]/, 'delimiter'],
      [/@symbols/, 'operator'],
      [/\s+/, 'white'],
    ],

    comment: [
      [/[^\/*]+/, 'comment'],
      [/\*\//, 'comment', '@pop'],
      [/[\/*]/, 'comment'],
    ],
  },
};

/* Two themes, and they are the same colours LE2's editor uses, on purpose:
 * someone who works in both should not have to re-learn what purple means. */
const rules = (dark) => [
  { token: 'keyword', foreground: dark ? 'c586c0' : 'af00db' },
  { token: 'keyword.declaration', foreground: dark ? '569cd6' : '0000ff', fontStyle: 'bold' },
  { token: 'type', foreground: dark ? '4ec9b0' : '267f99' },
  { token: 'predefined', foreground: dark ? 'dcdcaa' : '795e26' },
  { token: 'variable', foreground: dark ? '9cdcfe' : '001080' },
  { token: 'string', foreground: dark ? 'ce9178' : 'a31515' },
  { token: 'string.quoted', foreground: dark ? 'ce9178' : 'a31515' },
  { token: 'number', foreground: dark ? 'b5cea8' : '098658' },
  { token: 'number.date', foreground: dark ? 'b5cea8' : '098658' },
  { token: 'comment', foreground: dark ? '6a9955' : '008000' },
  { token: 'operator', foreground: dark ? 'd4d4d4' : '000000' },
];

export const themes = {
  'lps-dark': { base: 'vs-dark', inherit: true, rules: rules(true), colors: {} },
  'lps-light': { base: 'vs', inherit: true, rules: rules(false), colors: {} },
  'lps-hc': { base: 'hc-black', inherit: true, rules: rules(true), colors: {} },
};

/* Completions: the language's own words, plus a few whole constructs. Nothing
 * here needs the server, so it survives an unreachable one. */
const SNIPPETS = [
  { label: 'if … then …', insert: 'if   ${1:Condition} at T\nthen ${2:action} from T to T2.' },
  { label: 'initiates', insert: '${1:event} initiates ${2:fluent}.' },
  { label: 'terminates', insert: '${1:event} terminates ${2:fluent}.' },
  { label: 'updates … to … in …', insert: '${1:event} updates ${2:Old} to ${3:New} in ${4:fluent}(${2:Old}).' },
  { label: 'false (constraint)', insert: 'false ${1:conditions}.' },
  { label: 'observe', insert: 'observe ${1:event} from ${2:1} to ${3:2}.' },
  { label: 'initially', insert: 'initially ${1:fluent}.' },
  { label: 'achieve', insert: 'achieve ${1:fluent}.' },
  { label: 'display/2', insert: 'display(${1:fluent},\n\t[type:${2|rectangle,circle,ellipse,arrow,raster,star,text|}, point:[${3:X}, ${4:Y}], fillColor:${5:green}]).' },
  { label: 'display3d/2', insert: 'display3d(${1:fluent},\n\t[type:${2|box,sphere,cylinder,cone,plane|}, position:[${3:X}, ${4:Y}, ${5:Z}], size:[1,1,1], color:${6:green}]).' },
  { label: 'planning directive', insert: ':- lps_engine(planning, [search(auto), horizon(${1:12}), max_concurrency(${2:1})]).' },
];

export function registerLps(monaco) {
  monaco.languages.register({ id: LANGUAGE_ID, extensions: ['.lps', '.pl', '.lpsw', '.P'] });
  monaco.languages.setLanguageConfiguration(LANGUAGE_ID, languageConfiguration);
  monaco.languages.setMonarchTokensProvider(LANGUAGE_ID, monarchTokens);
  for (const [name, theme] of Object.entries(themes)) monaco.editor.defineTheme(name, theme);

  monaco.languages.registerCompletionItemProvider(LANGUAGE_ID, {
    provideCompletionItems(model, position) {
      const word = model.getWordUntilPosition(position);
      const range = {
        startLineNumber: position.lineNumber, endLineNumber: position.lineNumber,
        startColumn: word.startColumn, endColumn: word.endColumn,
      };
      const kw = (list, kind, detail) => list.map((label) => ({
        label, kind, detail, insertText: label, range,
      }));
      const K = monaco.languages.CompletionItemKind;
      return {
        suggestions: [
          ...kw(operators, K.Keyword, 'LPS operator'),
          ...kw(declarations, K.Property, 'declaration'),
          ...kw(systemPredicates, K.Function, 'system predicate'),
          ...kw(internals, K.Struct, 'internal syntax'),
          //  The program's own vocabulary, which is the half a fixed keyword
          //  list can never have. Comes from the server's analyse profile.
          ...kw(PROGRAM_EVENTS, K.Event, 'an event this program declares'),
          ...kw(PROGRAM_ACTIONS, K.Method, 'an action this program declares'),
          ...SNIPPETS.map((s) => ({
            label: s.label, kind: K.Snippet, insertText: s.insert,
            insertTextRules: monaco.languages.CompletionItemInsertTextRule.InsertAsSnippet,
            detail: 'construct', range,
          })),
        ],
      };
    },
  });

  /*  Occurrence highlighting, VS Code's: put the cursor on a name and every
   *  other use of it lights up. Monaco's wordHighlighter contribution asks a
   *  provider for the ranges, and without one the feature is inert — which is
   *  why the option alone did nothing. A text search is the right answer here
   *  for the same reason "show definition" uses one: it keeps working while the
   *  buffer does not compile. */
  monaco.languages.registerDocumentHighlightProvider(LANGUAGE_ID, {
    provideDocumentHighlights(model, position) {
      const w = model.getWordAtPosition(position);
      if (!w || w.word.length < 2) return [];
      return model.findMatches(w.word, true, false, true, null, false)
        .map((m) => ({ range: m.range, kind: monaco.languages.DocumentHighlightKind.Text }));
    },
  });

  /*  Folding by clause. Monaco's default strategy is indentation, and a Prolog
   *  file is not indented — which is why Edit ▸ Collapse all used to appear to
   *  do nothing at all. A clause is "a line starting in column 1 up to the line
   *  ending in a full stop", and a block comment is a region too. */
  monaco.languages.registerFoldingRangeProvider(LANGUAGE_ID, {
    provideFoldingRanges(model) {
      const lines = model.getLinesContent();
      const out = [];
      let i = 0;
      while (i < lines.length) {
        const l = lines[i];
        if (/^\s*\/\*/.test(l)) {
          let j = i;
          while (j < lines.length && !/\*\//.test(lines[j])) j++;
          if (j > i) out.push({ start: i + 1, end: j + 1, kind: monaco.languages.FoldingRangeKind.Comment });
          i = j + 1;
          continue;
        }
        if (/^[a-z'"]/.test(l) && !/\.\s*(%.*)?$/.test(l)) {
          let j = i;
          while (j < lines.length && !/\.\s*(%.*)?$/.test(lines[j])) j++;
          if (j > i && j < lines.length) out.push({ start: i + 1, end: j + 1 });
          i = j + 1;
          continue;
        }
        i++;
      }
      return out;
    },
  });

  monaco.languages.registerHoverProvider(LANGUAGE_ID, {
    provideHover(model, position) {
      const w = model.getWordAtPosition(position);
      if (!w) return null;
      const op = operatorTable.find((o) => o.name === w.word);
      if (op) {
        return {
          contents: [
            { value: `**${op.name}** — LPS operator` },
            { value: `\`op(${op.priority}, ${op.type}, ${op.name})\`` },
          ],
        };
      }
      if (declarations.includes(w.word)) {
        return { contents: [{ value: `**${w.word}** — declaration. See [the language reference](/docs/lps_summary).` }] };
      }
      if (internals.includes(w.word)) {
        return { contents: [{ value: `**${w.word}** — internal syntax (§I.3). Written by the translator; you rarely type it.` }] };
      }
      return null;
    },
  });
}

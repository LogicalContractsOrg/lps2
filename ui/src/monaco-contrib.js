/* monaco-contrib.js — the parts of Monaco that make it an editor.
 *
 * `vs/editor/editor.api.js` is the API and *nothing else*: no context menu, no
 * find widget, no folding, no occurrence highlighting. It is the right entry
 * point — `editor.main.js` also drags in ninety bundled languages, none of
 * which an LPS file has any use for, and triples the build — but importing it
 * alone produces an editor where right-click does nothing and Ctrl+F is a
 * browser search. That is exactly what this IDE shipped with.
 *
 * So: the API, plus the contributions worth having, named one at a time. Each
 * line here is a feature somebody would otherwise report as missing.
 *
 * The relative paths are deliberate, as in main.js: the package's exports map
 * rewrites `monaco-editor/esm/vs/...` into `./esm/vs/esm/vs/...` and nothing
 * resolves.
 */

/*  Right-click, and everything that appears in it. */
import '../node_modules/monaco-editor/esm/vs/editor/contrib/contextmenu/browser/contextmenu.js';
import '../node_modules/monaco-editor/esm/vs/editor/contrib/clipboard/browser/clipboard.js';

/*  Find and replace, and the selection highlight that comes with it: select a
 *  term and every other occurrence lights up, as in VS Code. */
import '../node_modules/monaco-editor/esm/vs/editor/contrib/find/browser/findController.js';

/*  Occurrence highlighting for the word under the cursor. Needs a highlight
 *  provider, which lps-language.js registers. */
import '../node_modules/monaco-editor/esm/vs/editor/contrib/wordHighlighter/browser/wordHighlighter.js';

/*  Folding, which is what Edit ▸ Collapse all drives. */
import '../node_modules/monaco-editor/esm/vs/editor/contrib/folding/browser/folding.js';

/*  Diagnostics in context: hover to read the message, F8 to walk them. This is
 *  what replaced the "no problems" strip under the editor. */
import '../node_modules/monaco-editor/esm/vs/editor/contrib/hover/browser/hoverContribution.js';
import '../node_modules/monaco-editor/esm/vs/editor/contrib/gotoError/browser/gotoError.js';

/*  Editing comfort a Prolog file wants: comment toggling, multi-cursor,
 *  line moves and duplication, bracket matching, smart selection, word-wise
 *  motion, indentation commands, and undoing a cursor jump. */
import '../node_modules/monaco-editor/esm/vs/editor/contrib/comment/browser/comment.js';
import '../node_modules/monaco-editor/esm/vs/editor/contrib/multicursor/browser/multicursor.js';
import '../node_modules/monaco-editor/esm/vs/editor/contrib/linesOperations/browser/linesOperations.js';
import '../node_modules/monaco-editor/esm/vs/editor/contrib/bracketMatching/browser/bracketMatching.js';
import '../node_modules/monaco-editor/esm/vs/editor/contrib/smartSelect/browser/smartSelect.js';
import '../node_modules/monaco-editor/esm/vs/editor/contrib/wordOperations/browser/wordOperations.js';
import '../node_modules/monaco-editor/esm/vs/editor/contrib/indentation/browser/indentation.js';
import '../node_modules/monaco-editor/esm/vs/editor/contrib/cursorUndo/browser/cursorUndo.js';
import '../node_modules/monaco-editor/esm/vs/editor/contrib/caretOperations/browser/transpose.js';
import '../node_modules/monaco-editor/esm/vs/editor/contrib/inPlaceReplace/browser/inPlaceReplace.js';
import '../node_modules/monaco-editor/esm/vs/editor/contrib/anchorSelect/browser/anchorSelect.js';
import '../node_modules/monaco-editor/esm/vs/editor/contrib/links/browser/links.js';

/*  Completion, so a half-typed declaration can be finished from the program's
 *  own vocabulary. The provider is in lps-language.js. */
import '../node_modules/monaco-editor/esm/vs/editor/contrib/suggest/browser/suggestController.js';

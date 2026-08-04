/* why.js — "why did that happen?", asked where the thing is.
 *
 * The explain pane was a text field in a tab nobody opened. You had to know the
 * question's syntax, and you had to type the term — which meant reading it off
 * another pane first. That is backwards: the panes are *full* of terms, and
 * every one of them is a thing you might want explained.
 *
 * So there is no explain pane. Instead every visualiser marks its elements with
 * what they represent, and a right-click on any of them opens this modal, which
 * asks the question you would have typed. The "why not" field is there because
 * the interesting question is often about the term that is *absent*, and the
 * panes cannot show you those — so it suggests the shapes.
 */
import { el } from './panes/basic.js';

let deps = null;
export function initWhy(d) { deps = d; }

/*  A pane element becomes askable by carrying these. Nothing else in a pane has
 *  to know this file exists.
 *
 *  `kind` is what to ask about it: `fluent` (why does it hold), `stopped` (why
 *  did it stop — the old half of an update), or `event`. */
export function askable(node, { term, kind, cycle }) {
  node.dataset.lpsTerm = term;
  node.dataset.lpsKind = kind;
  if (cycle !== undefined && cycle !== null) node.dataset.lpsCycle = String(cycle);
  node.classList.add('askable');
  return node;
}

/*  The canvas panes cannot delegate — Konva and three.js draw to one element
 *  each — so they hit-test themselves and announce the result. */
window.addEventListener('lps-why', (e) => {
  if (!deps) return;
  openWhy({ term: e.detail.term, kind: e.detail.kind, cycle: deps.state.cycle });
});

/** Attach one delegated listener per pane. */
export function wireWhy(pane) {
  if (pane.dataset.whyWired) return;
  pane.dataset.whyWired = '1';
  pane.addEventListener('contextmenu', (e) => {
    const node = e.target.closest?.('.askable');
    if (!node) return;
    e.preventDefault();
    openWhy({
      term: node.dataset.lpsTerm,
      kind: node.dataset.lpsKind,
      cycle: node.dataset.lpsCycle !== undefined ? Number(node.dataset.lpsCycle) : deps.state.cycle,
    });
  });
}

const questionFor = (kind, term, cycle) => {
  if (kind === 'stopped') return `why(stopped(${term}), ${cycle})`;
  if (kind === 'fluent') return `why(holds(${term}), ${cycle})`;
  return `why(happened(${term}), ${cycle})`;
};

export async function openWhy({ term, kind, cycle }) {
  const st = deps.state;
  if (!st.session) { deps.setStatus('run the program first'); return; }
  const c = Number.isFinite(cycle) ? cycle : st.cycle;

  const answer = el('div', { class: 'why-answer' }, el('p', { class: 'empty', text: 'asking…' }));
  const q = questionFor(kind, term, c);

  const goToLine = (line) => {
    const ed = deps.state.editor;
    ed.revealLineInCenter(line);
    ed.setPosition({ lineNumber: line, column: 1 });
    ed.focus();
    deps.closeDialog();
  };

  /*  The counterfactual half.
   *
   *  It is prefilled with the *same* term, because "why did this not happen
   *  instead" is usually a question about a near variant — and the field takes
   *  a bare term, not a whole question. Wrapping it here is what makes it work
   *  for a fluent as well as an action: `why_not(holds(F), T)` and
   *  `why_not(happened(A), T)` are different question forms, and asking the
   *  wrong one used to come back "the question form is not recognised". */
  const isFluent = kind === 'fluent' || kind === 'stopped';
  const notInput = el('input', {
    class: 'why-not',
    value: term,
    title: 'a term that did not happen, or does not hold, at this cycle',
  });
  const notKind = el('select', { class: 'why-kind' },
    el('option', { value: 'holds', text: 'does not hold' }),
    el('option', { value: 'happened', text: 'did not happen' }));
  notKind.value = isFluent ? 'holds' : 'happened';

  const notGo = el('button', { text: 'Why not?' });
  const ask = async (question) => {
    answer.replaceChildren(el('p', { class: 'empty', text: 'asking…' }));
    try {
      const e = await deps.api.explain(st.session, question);
      deps.renderExplanation(answer, e, goToLine);
    } catch (err) {
      answer.replaceChildren(el('p', { class: 'empty', text: err.message }));
    }
  };
  const askNot = () => {
    const t = notInput.value.trim();
    if (!t) return;
    ask(`why_not(${notKind.value}(${t}), ${c})`);
  };
  notGo.addEventListener('click', askNot);
  notInput.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') askNot(); });

  deps.openDialog(`${term} — cycle ${c}`,
    el('div', { class: 'why' },
      el('div', { class: 'why-q' }, el('code', { text: q })),
      answer,
      el('div', { class: 'why-notrow' },
        el('span', { class: 'muted', text: 'and why' }), notKind, notInput, notGo)));
  ask(q);
}

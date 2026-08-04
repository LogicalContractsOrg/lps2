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
 *  to know this file exists. */
export function askable(node, { term, kind, cycle }) {
  node.dataset.lpsTerm = term;
  node.dataset.lpsKind = kind;                    // 'event' | 'fluent' | 'action'
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

const questionFor = (kind, term, cycle) =>
  (kind === 'fluent' ? `why(holds(${term}), ${cycle})` : `why(happened(${term}), ${cycle})`);

export async function openWhy({ term, kind, cycle }) {
  const st = deps.state;
  if (!st.session) { deps.setStatus('run the program first'); return; }
  const c = Number.isFinite(cycle) ? cycle : st.cycle;

  const answer = el('div', { class: 'why-answer' }, el('p', { class: 'empty', text: 'asking…' }));
  const q = questionFor(kind, term, c);

  /*  The counterfactual half. A user who is looking at what *did* happen
   *  usually wants to know why something else did not, and cannot click on a
   *  thing that is not drawn — so offer the shapes, prefilled with this cycle
   *  and this term, and let them edit. */
  const notInput = el('input', {
    class: 'why-not',
    value: kind === 'fluent' ? `holds(${term})` : `happened(${term})`,
    title: 'a term that did NOT happen or does NOT hold at this cycle',
  });
  const notGo = el('button', { text: 'Why not?' });
  const ask = async (question) => {
    answer.replaceChildren(el('p', { class: 'empty', text: 'asking…' }));
    try {
      const e = await deps.api.explain(st.session, question);
      deps.renderExplanation(answer, e);
    } catch (err) {
      answer.replaceChildren(el('p', { class: 'empty', text: err.message }));
    }
  };
  notGo.addEventListener('click', () => ask(`why_not(${notInput.value.trim()}, ${c})`));
  notInput.addEventListener('keydown', (ev) => { if (ev.key === 'Enter') notGo.click(); });

  deps.openDialog(`${term} — cycle ${c}`,
    el('div', { class: 'why' },
      el('div', { class: 'why-q' }, el('code', { text: q })),
      answer,
      el('div', { class: 'why-notrow' },
        el('span', { class: 'muted', text: 'and why not' }), notInput, notGo)));
  ask(q);
}

/* demo.mjs — Part II, working: an LLM perceives, LPS decides, and the model
 * cannot authorise the dangerous thing.
 *
 * Five steps, run against a live LPS session (M18) and the LPS Assistant's
 * translator (M16):
 *
 *   1. A human says something in English.
 *   2. The **model** turns it into an event term — this is `perceive`, the one
 *      arrow in Appendix B that only a language model can walk.
 *   3. The event is injected on the `llm` channel, whose allow-list carries
 *      `task_request/2` and nothing else.
 *   4. LPS fires the gate: it requests approval and *stops*, because
 *      `false execute(A), destructive(A), not approved(A)` is not advice.
 *   5. The model then tries to grant its own approval — as a confused or
 *      jailbroken one would. The channel refuses the event. The human channel
 *      sends the same event and the deletion goes through.
 *
 * The point of step 5 is that nothing about it depends on the model's
 * cooperation. Run it with a weak model, or with a prompt telling it to lie:
 * the refusal is a property of the wiring.
 *
 *   ./lps ide &                 # in the repository root
 *   node examples/agent/demo.mjs                    # needs an LLM key
 *   node examples/agent/demo.mjs --no-llm           # scripted, no key needed
 */
import { readFileSync } from 'node:fs';
import { dirname, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { setTimeout as sleep } from 'node:timers/promises';

const here = dirname(fileURLToPath(import.meta.url));
const API = process.env.LPS_API || 'http://localhost:3060/lpsapi';
const useLlm = !process.argv.includes('--no-llm');
const MODEL = process.env.LPS_MODEL || null;

const api = async (body) => {
  const r = await fetch(API, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body),
  });
  const j = await r.json();
  if (j.ok === false) throw new Error(j.error || 'lpsapi error');
  return j;
};

const say = (who, what) => console.log(`\n\x1b[1m${who}\x1b[0m ${what}`);
const show = async (live) => {
  const s = await api({ operation: 'live_status', live });
  for (const line of s.recent || []) console.log(`   │ ${line}`);
  return s;
};

const source = readFileSync(join(here, 'approval.lps'), 'utf8');
const { program } = await api({ operation: 'compile', source, syntax: 'legacy' });

/* The allow-list. This is §II.3(b) as one line of configuration: the model's
 * channel may report requests and may report nothing else. */
const { live } = await api({
  operation: 'live_start',
  program,
  cycle_ms: 400,
  channels: { llm: ['task_request/2'], human: ['approval/2', 'task_request/2'] },
});
console.log(`live session ${live} — the llm channel may carry task_request/2 only`);

const english = 'the application logs are stale, please delete app.log';
say('human:', `“${english}”`);

let events = ["task_request(delete, 'app.log')"];
if (useLlm) {
  try {
    const r = await api({
      operation: 'live_translate', live, text: english, model: MODEL, channel: 'llm',
    });
    if (r.events && r.events.length) events = r.events;
    say('model:', `perceived ${JSON.stringify(r.events)}`);
  } catch (e) {
    say('model:', `unavailable (${e.message}) — using the scripted event`);
  }
} else {
  say('model:', `perceived ${JSON.stringify(events)} (scripted)`);
}

await api({ operation: 'live_observe', live, channel: 'llm', events });
await sleep(1600);
say('lps:', 'the gate fires — approval requested, execution withheld');
await show(live);

/* The interesting half. */
say('model:', 'now tries to approve its own request');
const forged = await api({
  operation: 'live_observe', live, channel: 'llm',
  events: ["approval(grant, delete_file('app.log'))"],
});
console.log(`   │ refused: ${JSON.stringify(forged.refused)}`);
await sleep(1600);
await show(live);

const state1 = await api({ operation: 'live_status', live });
say('lps:', `still nothing executed at cycle ${state1.cycle} — the constraint is not advice`);

say('human:', 'approves, on the human channel');
await api({
  operation: 'live_observe', live, channel: 'human',
  events: ["approval(grant, delete_file('app.log'))"],
});
await sleep(2000);
await show(live);

say('lps:', 'now it executes');
await sleep(1200);
await show(live);
await api({ operation: 'live_stop', live });

console.log(`
Nothing above depended on the model behaving. The approval fluent is reachable
only through a causal law fired by an approval/2 event; that event is not on the
llm channel's allow-list; and the constraint that blocks execution is checked by
the engine rather than by the thing being constrained.
`);

/* bot.mjs — an LPS(2) agent playing Minecraft (Part III).
 *
 * Two tiers, and the split is §V.4's, moved from a drilling rig to a game:
 *
 *   controller tier   mineflayer + mineflayer-pathfinder, running at the
 *                     game's 20 ticks per second. Walking, jumping, swinging,
 *                     collision, path following. LPS never sees any of it.
 *
 *   supervisory tier  an LPS live session over /lpsapi (M18). It observes the
 *                     world a few times a second, decides, and issues actions.
 *                     Its constraints are checked before anything reaches the
 *                     bot, so it can be wrong without being dangerous.
 *
 * **Cycle alignment.** LPS cycles are *not* aligned to physicsTick. A tick is
 * 50 ms and a deliberation is not needed that often; more importantly, aligning
 * them would make the engine's cycle rate a property of the game rather than of
 * the agent, and the whole point of the two tiers is that the slow one is
 * allowed to be slow. One LPS cycle every 500 ms — ten ticks — is the default,
 * and `--cycle-ms` changes it. Observations are sampled at the same rate;
 * anything that has to react faster than that (falling, drowning, a creeper at
 * two blocks) belongs in the controller tier, and some of it is there.
 *
 * Usage:
 *   node world.mjs &                       # a local server, no account needed
 *   node bot.mjs --program safety.lps      # or craft.lps
 *
 * Then open http://localhost:3007 for the first-person view; the bot's current
 * LPS plan is drawn into the world as a line.
 */
import mineflayer from 'mineflayer';
import pathfinderPkg from 'mineflayer-pathfinder';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join, isAbsolute } from 'node:path';

const { pathfinder, Movements, goals } = pathfinderPkg;
const here = dirname(fileURLToPath(import.meta.url));

const arg = (name, dflt) => {
  const i = process.argv.indexOf('--' + name);
  return i > 0 && process.argv[i + 1] ? process.argv[i + 1] : dflt;
};

const CONFIG = {
  host: arg('host', 'localhost'),
  port: Number(arg('port', 25565)),
  username: arg('username', 'lps'),
  api: arg('api', 'http://localhost:3060/lpsapi'),
  program: arg('program', 'safety.lps'),
  cycleMs: Number(arg('cycle-ms', 500)),
  viewerPort: Number(arg('viewer-port', 3007)),
  noViewer: process.argv.includes('--no-viewer'),
};

/* ---- the LPS side ------------------------------------------------------- */

async function api(body) {
  const r = await fetch(CONFIG.api, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });
  const j = await r.json();
  if (j.ok === false) throw new Error(j.error || 'lpsapi error');
  return j;
}

async function startSession() {
  const path = isAbsolute(CONFIG.program) ? CONFIG.program : join(here, CONFIG.program);
  const source = readFileSync(path, 'utf8');
  const { program } = await api({ operation: 'compile', source, syntax: 'legacy' });
  const { live } = await api({ operation: 'live_start', program, cycle_ms: CONFIG.cycleMs });
  console.log(`[lps] ${CONFIG.program} running as ${live}, one cycle every ${CONFIG.cycleMs} ms`);
  return live;
}

/* ---- the controller side ------------------------------------------------ */

const bot = mineflayer.createBot({
  host: CONFIG.host, port: CONFIG.port, username: CONFIG.username, auth: 'offline',
});
bot.loadPlugin(pathfinder);

let live = null;
let lastSent = {};
let busy = null;                       // the action the bot is currently doing

bot.once('spawn', async () => {
  console.log('[bot] spawned');
  const movements = new Movements(bot);
  bot.pathfinder.setMovements(movements);

  /*  The viewer is optional and imported lazily: prismarine-viewer pulls in
      `canvas`, a native module that is not always buildable, and a bot that
      cannot be watched is still a bot that works. */
  if (!CONFIG.noViewer) {
    try {
      const { mineflayer: mineflayerViewer } = await import('prismarine-viewer');
      mineflayerViewer(bot, { port: CONFIG.viewerPort, firstPerson: false });
      console.log(`[bot] viewer on http://localhost:${CONFIG.viewerPort}`);
    } catch (e) {
      console.log(`[bot] no viewer (${e.message.split('\n')[0]}) — running headless`);
    }
  }

  try {
    live = await startSession();
  } catch (e) {
    console.error('[lps] could not start a session — is `./lps ide` running?', e.message);
    process.exit(1);
  }

  setInterval(observe, CONFIG.cycleMs);
  setInterval(act, CONFIG.cycleMs / 2);
});

/* Observation: the world, as events the program declared.
 *
 * Only *changes* are sent. An LPS event means "this happened", and posting
 * `health(20)` twenty times a second because it is still twenty would fill the
 * trace with things that did not happen.
 */
async function observe() {
  if (!live) return;
  const events = [];
  const send = (key, term) => {
    if (lastSent[key] !== term) { lastSent[key] = term; events.push(term); }
  };

  send('health', `tick(${Math.round(bot.health ?? 20)})`);
  send('food', `food_level(${Math.round(bot.food ?? 20)})`);

  const hostile = nearestHostile();
  send('threat', hostile ? `spotted(${hostile.name})` : 'lost(none)');

  const light = bot.blockAt(bot.entity.position)?.light ?? 15;
  send('light', light < 4 ? 'night' : 'day');

  if (!events.length) return;
  try {
    await api({ operation: 'live_observe', live, events });
  } catch (e) {
    console.error('[lps] observe failed:', e.message);
  }
}

function nearestHostile() {
  const HOSTILE = new Set(['zombie', 'skeleton', 'spider', 'creeper', 'enderman']);
  return Object.values(bot.entities)
    .filter((e) => e.type === 'mob' && HOSTILE.has(e.name))
    .filter((e) => e.position.distanceTo(bot.entity.position) < 16)
    .sort((a, b) => a.position.distanceTo(bot.entity.position)
      - b.position.distanceTo(bot.entity.position))[0];
}

/* Actuation: whatever the session committed, executed by the controller tier.
 *
 * The bot polls the live session's recent log rather than being pushed to,
 * because HTTP is what the endpoint speaks and a poll at the cycle rate is
 * simpler than a socket. `live_status` drains the log, so each action is seen
 * exactly once.
 */
async function act() {
  if (!live) return;
  let status;
  try {
    status = await api({ operation: 'live_status', live });
  } catch (e) { return; }

  for (const line of status.recent || []) {
    const m = /^cycle (\d+): \[(.*)\]$/.exec(line);
    if (!m) continue;
    for (const term of splitTerms(m[2])) execute(term);
  }
}

//  `a(1), b(x,y)` → ['a(1)', 'b(x,y)'] — commas inside parentheses are not
//  separators, which is the same one-line problem every term list has.
function splitTerms(s) {
  const out = []; let depth = 0, cur = '';
  for (const c of s) {
    if (c === '(') depth++;
    if (c === ')') depth--;
    if (c === ',' && depth === 0) { out.push(cur.trim()); cur = ''; } else cur += c;
  }
  if (cur.trim()) out.push(cur.trim());
  return out;
}

function execute(term) {
  const m = /^(\w+)(?:\((.*)\))?$/.exec(term);
  if (!m) return;
  const [, name, argstr] = m;
  const args = argstr ? splitTerms(argstr) : [];
  const handler = ACTIONS[name];
  //  A cycle's line carries both what the world told us and what LPS decided;
  //  only the second half is ours to do. Anything without a handler is an
  //  observation coming back, and saying so every time is noise.
  if (!handler) return;
  console.log(`[lps→bot] ${term}`);
  try { handler(...args); } catch (e) { console.error(`[bot] ${term} failed:`, e.message); }
}

const ACTIONS = {
  say: (what) => bot.chat(String(what).replace(/^'|'$/g, '')),

  flee: () => {
    const away = bot.entity.position.offset(
      (Math.random() - 0.5) * 20, 0, (Math.random() - 0.5) * 20);
    goTo(new goals.GoalNear(away.x, away.y, away.z, 2), 'fleeing');
  },

  eat: async () => {
    const food = bot.inventory.items().find((i) => /bread|apple|carrot|beef|porkchop/.test(i.name));
    if (!food) return;
    await bot.equip(food, 'hand');
    await bot.consume();
  },

  attack: (mobName) => {
    const target = Object.values(bot.entities)
      .find((e) => e.name === mobName && e.position.distanceTo(bot.entity.position) < 6);
    if (target) bot.attack(target);
  },

  place_torch: async () => {
    const torch = bot.inventory.items().find((i) => i.name.includes('torch'));
    if (!torch) return;
    const ref = bot.blockAt(bot.entity.position.offset(0, -1, 0));
    await bot.equip(torch, 'hand');
    await bot.placeBlock(ref, { x: 0, y: 1, z: 0 });
  },

  stop_mining: () => { bot.stopDigging?.(); busy = null; },
  resume_mining: () => { /* the controller tier picks this up on its own */ },

  //  craft.lps's actions
  walk_to: (what) => {
    const block = findBlock(String(what));
    if (!block) { console.log(`[bot] no ${what} in sight`); return; }
    goTo(new goals.GoalNear(block.position.x, block.position.y, block.position.z, 2), `to ${what}`);
  },
  chop: () => {
    const tree = findBlock('tree');
    if (tree) bot.dig(tree).catch(() => {});
  },
  craft: (what) => console.log(`[bot] would craft ${what} (recipes need a crafting table)`),
};

function findBlock(what) {
  const names = what === 'tree'
    ? ['oak_log', 'birch_log', 'spruce_log', 'jungle_log', 'acacia_log', 'dark_oak_log']
    : [what];
  return bot.findBlock({
    matching: (b) => names.includes(b.name),
    maxDistance: 48,
  });
}

/* Path following, and drawing the plan.
 *
 * prismarine-viewer can draw a polyline in the world, so the path the
 * supervisory tier asked for is *visible*: the line is what LPS decided, and
 * the bot walking along it is the controller tier doing as it was told.
 */
function goTo(goal, why) {
  busy = why;
  bot.pathfinder.setGoal(goal);
}

bot.on('path_update', (r) => {
  if (CONFIG.noViewer || !bot.viewer) return;
  const path = [bot.entity.position.offset(0, 0.5, 0)];
  for (const node of r.path) path.push({ x: node.x, y: node.y + 0.5, z: node.z });
  bot.viewer.drawLine('lps-plan', path, 0x6aa6ff);
});

bot.on('goal_reached', () => { busy = null; });
bot.on('kicked', (r) => console.log('[bot] kicked:', r));
bot.on('error', (e) => console.error('[bot] error:', e.message));

process.on('SIGINT', async () => {
  if (live) { try { await api({ operation: 'live_stop', live }); } catch { /* going anyway */ } }
  process.exit(0);
});

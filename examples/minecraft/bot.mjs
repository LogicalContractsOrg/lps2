/* bot.mjs — an LPS2 agent playing Minecraft (Part III).
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

//  Long enough that a server generating chunks for the first time is not
//  accused of anything; short enough to be seen before the demo's own timer.
const SPAWN_TIMEOUT_MS = 25000;

/* ---- the LPS side ------------------------------------------------------- */

//  The first line of a multi-line native-module failure — the part that names
//  the cause. A dlopen dump is six lines of paths tried.
function firstLine(e) {
  const m = String((e && e.message) || e).split('\n')[0];
  return m.length > 110 ? m.slice(0, 107) + '…' : m;
}

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
let inTheVoid = false;                 // said once, not once a cycle

/*  Connecting and spawning are two different things, and the gap between them
 *  is where this demo used to die in silence: the server accepts the login,
 *  logs "spawning player", and then mineflayer waits for the chunk the player
 *  is standing in. If the saved position is outside the world — a bot that fell
 *  into the void in an earlier run, saved at y = -13826 — that chunk never
 *  comes, `spawn` never fires, and every line below this one is unreachable.
 *  Nothing is printed, nothing listens on the viewer port, and the only symptom
 *  is a bot that does nothing for ever. So: say so. */
const spawnWatchdog = setTimeout(() => {
  console.error(`[bot] connected to ${CONFIG.host}:${CONFIG.port} but never spawned `
    + `after ${SPAWN_TIMEOUT_MS / 1000}s.`);
  console.error('[bot] the usual cause is a saved player position outside the world.');
  console.error('[bot] with the bundled world:  npm run reset   (then start world.mjs again)');
}, SPAWN_TIMEOUT_MS);

bot.once('spawn', async () => {
  clearTimeout(spawnWatchdog);
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
      /*  One line, and then where to go. The failure is nearly always
          `canvas`, whose message is a dlopen dump several lines long that says
          what went wrong and nothing about what to do; `npm run doctor` is the
          long answer, and it does not belong in a bot's log. */
      console.log(`[bot] no viewer — running headless. ${firstLine(e)}`);
      console.log('[bot] why, and how to fix it:  npm run doctor        '
        + '(or --no-viewer to stop trying)');
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

  //  Falling out of the world is not something LPS can be asked about — none of
  //  the programs declare an event for it and no action would help. It is not
  //  sent, then; it is said once, because the position gets saved and it is
  //  what breaks the *next* run.
  const below = bot.entity.position.y < (bot.game?.minY ?? -64);
  if (below && !inTheVoid) {
    console.error(`[bot] below the world (y=${Math.round(bot.entity.position.y)}) — `
      + 'this position will be saved; run `npm run reset` before the next run');
  }
  inTheVoid = below;

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
 * simpler than a socket. `live_status` drains the log, so each line is seen
 * exactly once.
 *
 * The line format is `lps_live.pl`'s `report_line/3`:
 *
 *     2  ·  chop(tree)  walk_to(tree)  near(nothing) → near(tree)
 *     3  ·  chop(tree)  craft(plank)  +has(log)
 *
 * — a cycle number, U+00B7, and the parts joined by *two* spaces, which is why
 * a term with a single space inside it (`say('breaking off')`) survives the
 * split. Parts are of three kinds and only the first is ours: things that
 * happened, and fluents that started (`+f`), stopped (`-f`), or changed
 * (`a → b`).
 *
 * An action spanning T to T+1 is reported in both cycles, so the same term
 * arrives twice running. It is executed once.
 */
async function act() {
  if (!live) return;
  let status;
  try {
    status = await api({ operation: 'live_status', live });
  } catch (e) { return; }

  for (const line of status.recent || []) {
    const m = /^(\d+)\s+·\s+(.*)$/.exec(line);
    //  Everything else the session says — "paused", "ended: …", "error: …" —
    //  is worth seeing but is not an instruction.
    if (!m) { if (line.trim()) console.log(`[lps] ${line}`); continue; }
    const happened = m[2].split(/ {2,}/)
      .map((p) => p.trim())
      .filter((p) => p && !/^[+\-~]/.test(p) && !p.includes('→') && p !== '(nothing happened)');
    for (const term of happened) {
      if (!lastCycle.has(term)) execute(term);
    }
    lastCycle = new Set(happened);
  }
}

let lastCycle = new Set();             // what the previous cycle reported

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

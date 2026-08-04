# An LPS2 agent in Minecraft

Part III of the plan asks for a Minecraft surface, "route (i): a Mineflayer JS
bot talking to the LPS endpoint". This is that, with the **two-tier
architecture** of §V.4 moved from a drilling rig to a game:

| tier | what runs there | rate |
|---|---|---|
| **controller** | `bot.mjs` + mineflayer + mineflayer-pathfinder: walking, jumping, swinging, collision, path following | the game's 20 ticks/second |
| **supervisory** | an LPS live session (M18): maintenance goals, constraints, plans, explanations | one cycle every 500 ms by default |

The split is the point. The supervisory tier **can be wrong without being
dangerous**, because every action it issues is still filtered by the program's
constraints before the controller tier sees it — the same argument as §II.3's
approval gate, instantiated in a game instead of a rig.

**Cycle alignment.** LPS cycles are deliberately *not* aligned to `physicsTick`.
A tick is 50 ms; deliberation does not need to happen twenty times a second, and
aligning them would make the engine's rate a property of the game rather than of
the agent. Anything that has to react faster than a cycle — falling, drowning,
a creeper at two blocks — belongs in the controller tier.

## Running it without buying Minecraft

You need no account, no client and no purchase: **flying-squid** is a Minecraft
server in JavaScript, and the bot connects to it in offline mode.

```sh
npm install                     # in this directory
cd ../.. && ./lps ide &         # the LPS server, on :3060
cd examples/minecraft

node world.mjs &                # a local server on :25565
node bot.mjs --program safety.lps
```

or all three at once:

```sh
node demo.mjs --program safety.lps --seconds 60
```

Against a real server instead: `node bot.mjs --host … --port …`. The bot does
not care which it is talking to.

**Watching it.** `prismarine-viewer` serves a browser view on
<http://localhost:3007> and draws the bot's current path as a blue line — which
is the *supervisory* tier's decision made visible, with the controller tier
walking it.

The viewer renders map tiles server-side and therefore needs **`canvas`**, a
native module. It is in `package.json`, so `npm install` gets it, and on macOS,
Windows and mainstream Linux npm downloads a prebuilt binary — no compiler
involved. If your platform has no prebuild, npm falls back to building from
source and wants Cairo and Pango:

```sh
brew install pkg-config cairo pango libpng jpeg giflib librsvg    # macOS
sudo apt install build-essential libcairo2-dev libpango1.0-dev \
     libjpeg-dev libgif-dev librsvg2-dev                          # Debian/Ubuntu
```

Windows prebuilds cover every supported Node version, so the fallback should
not arise. `bot.mjs` imports the viewer lazily either way: if `canvas` is
missing it prints `no viewer (Cannot find module 'canvas') — running headless`
and carries on, because a bot that cannot be watched is still a bot that works.

## The programs

### `safety.lps` — maintenance goals that interrupt

Health, food, light and threats arrive as events; the program decides. The
demonstration is the first rule:

```prolog
if   health(H) at T, H < 8
then stop_mining from T to T2,
     flee(danger) from T2 to T3,
     say('breaking off — health low') from T3 to T4.
```

That is not a suggestion weighed against whatever the bot is doing. It fires the
moment health drops and `stop_mining` goes out in the same cycle: the dig is
abandoned. A maintenance goal is not a task on a list.

### `hungry.lps` — a constraint blocking an action, and explaining itself

Hunger makes the bot hunt. Being hurt makes that a bad idea, and the constraint
says so:

```prolog
false attack(Mob) from T1 to _, passive(Mob), health(H) at T1, H < 15.
```

Run it and ask:

```sh
./lps run examples/minecraft/hungry.lps
./lps explain examples/minecraft/hungry.lps --ask "why_not(happened(attack(cow)), 4)"
```

```
[blocked_by_denial]
attack(cow) did not occur at cycle 4
  a denial blocked attack(cow) — false [happens(attack(cow),3,4), passive(cow),
                                        holds(health(4),3), 4<15]
```

The answer names the clause and the bindings that made it fire. Not "the agent
decided not to" — *this rule refused, on these grounds*.

### `craft.lps` — planning over crafting

```prolog
achieve has(wooden_pickaxe).
```

and the planner finds the chain: walk to a tree, chop it, planks, sticks,
pickaxe. Nothing in the file says how; the recipes are causal laws and the tool
requirements are denials.

```sh
./lps run examples/minecraft/craft.lps
```

```
events/2  [walk_to(tree)]
events/3  [chop(tree)]
events/4  [craft(plank)]
events/5  [craft(stick)]
events/6  [craft(wooden_pickaxe)]
```

The plan is a list of action sets executed one per cycle, so a plan that stops
being valid — the tree is gone, someone took the log — fails at execution and
replans against the state the bot is actually in (§I.7.6).

`has(Item)` is deliberately a boolean rather than a count. With counts, every
intermediate quantity is a distinct state and the search spends its time
deciding whether to chop a fourth log; what the plan is *about* is the order.
Counting is the controller tier's job.

## What this is not

It is a demonstration of the interface, not a good Minecraft player. The bot has
no combat tactics, no inventory management and no understanding of the world
beyond what `safety.lps` names. What it does have is a decision layer you can
interrogate: every action it took has a `why`, and every action it declined has
a `why_not`.

The open question §III names is still open and this does not answer it: whether
the state store survives a domain where fluent counts are orders of magnitude
larger than anything in the corpus. Here the bot observes four things.

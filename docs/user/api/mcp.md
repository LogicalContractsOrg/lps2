# LPS over MCP: a world an agent can ask

*Kind: reference · Audience: developers · Status: current (2026-09-18)*

The LPS2 server speaks MCP, the
[Model Context Protocol](https://modelcontextprotocol.io), which is the agreed
way for a language model to call on an outside program
(`src/edges/lps_mcp.pl`). So a language model — Claude Desktop, Claude Code,
opencode, or anything else that speaks MCP — can open an LPS (Logic Production
System) program as a **world**, watch that world, ask whether an action is
allowed *before* taking it, look ahead at what would follow, and ask why what
happened happened.

What LPS offers here is a different thing from what
[Logical English over MCP](https://le2.logicalcontracts.com/docs/user/api/mcp)
offers, and the two fit together. LE (Logical English) answers *what follows
from these facts*. LPS answers *what happens next, what is permitted now, and
what must never become true*.

## Table of Contents

- [Why an agent wants this](#why-an-agent-wants-this)
- [Transports](#transports)
- [Client setup](#client-setup)
- [Worlds](#worlds)
- [Tools](#tools)
  - [Finding and opening](#finding-and-opening)
  - [The guardrail](#the-guardrail)
  - [Looking ahead](#looking-ahead)
  - [Reading the run](#reading-the-run)
- [Prompts](#prompts)
- [Resources](#resources)
- [Protocol details](#protocol-details)
- [What this is not](#what-this-is-not)

## Why an agent wants this

A language model asked to act in a world with rules has three problems it
cannot solve out of what it has learned. The model does not know what is true
now. The model cannot reliably work out what follows from a sequence of
actions. And the model has no way of being *stopped* by a rule, as opposed to
being merely reminded of one.

An LPS program answers all three, because an LPS program is a machine that
holds a state and changes that state by law:

| The agent's question | The tool | What answers it |
|---|---|---|
| What is true now? | `state`, `timeline` | the current state of the run, not a recollection |
| May I do this? | `propose_action`, `may` | the program's integrity constraints, evaluated against the state the world is actually in |
| What happens if I do? | `simulate`, `what_would_violate`, `plan` | a run on a copy of the world |
| What just happened, and why? | `explain`, `changes`, `find_first` | the recorded trace, with the law and the line that caused each change |
| What do I still owe? | `obligations` | the goals reactive rules created and nothing has discharged |

The guardrail is the point. `propose_action` does not ask the model to be
careful. `propose_action` asks the engine, and the engine answers with the
constraint that refuses the action and with the conditions that make the
constraint apply:

```json
{"action": "transfer(fariba, 500, bob)",
 "permitted": false,
 "refused_by": [{"reads": "never transfer(A,B,C) while balance(A,F) and F<B",
                 "because": "balance(fariba,90) and 90<500",
                 "at": "bank_transfer.le:33",
                 "refuses": "transfer(fariba,500,bob)"}],
 "note": "the world was not advanced"}
```

## Transports

- **STDIO**, the plain input and output channels: `./lps mcp` reads one
  JSON-RPC message per line on standard input — a message written in JSON-RPC,
  which is a request in the JSON text format — and writes one reply per line
  on standard output. Run the command from the top folder of the project,
  because the examples and documents are found by paths relative to it.
- **HTTP**, over the web: send `POST /mcp` to the IDE server (`./lps ide`,
  port 3060 unless you change it), with one JSON-RPC message in each request.
  `GET /mcp` answers `405`, because this server does not offer a stream of
  events pushed out to the client.

A server started with `LPS_TOKEN` accepts that token at the MCP address either
as `Authorization: Bearer <token>` or as `?token=` on the URL. An MCP client
has nowhere to put the `token` field that `/lpsapi` operations use, which is
why the token goes in one of those two places instead.

With a copy of Logical English on the machine
(`LPS_LE2_LIB=<path to LogicalEnglish2>`), the server also opens `.le`
programs. Those are written in LE for LPS, the language people read and write,
and they include the twins migrated from Daml, Solidity and Drools programs.

## Client setup

Claude Desktop, `claude_desktop_config.json` — a local STDIO server:

```json
{
  "mcpServers": {
    "lps": { "command": "/path/to/lps2/lps", "args": ["mcp"] }
  }
}
```

or a server already running, reached through `mcp-remote`, a small program
that passes the messages along:

```json
{
  "mcpServers": {
    "lps": { "command": "npx", "args": ["mcp-remote", "http://localhost:3060/mcp"] }
  }
}
```

Claude Code, from the top folder of the project:

```bash
claude mcp add lps -- ./lps mcp
claude mcp add lps -- npx mcp-remote http://localhost:3060/mcp
```

## Worlds

An MCP conversation is not a session, so the server hands out a named handle
for each world. A **world** is one of two things:

- **owned** — a session this server created with `open_world`, and advances
  when you call `observe`; or
- **attached** — a handle that reads a *live* session somebody else is driving
  (`list_live`, `attach_live`). Every reading tool works the same way on an
  attached world. `observe` on an attached world sends the events to whoever
  is driving that session, rather than stepping the session itself.

Two rules hold for every tool:

1. **Asking is free.** `propose_action`, `may`, `simulate`,
   `what_would_violate` and `plan` run on a copy. The world's cycle is the
   same after the call as before it, and each reply says so.
2. **Acting is explicit.** Only `observe` advances an owned world.

A world lives in the memory of the running server, and a world's handle
carries a mark identifying that server (`w3-1de44f`). A handle from a
different server is therefore refused, rather than mistaken for one of this
server's own.

## Tools

### Finding and opening

| Tool | Arguments | Reply |
|---|---|---|
| `list_programs` | `match` | `{programs: [{name, title}]}` — the shipped examples, the LE-for-LPS programs, the migrated twins |
| `open_world` | `program` \| `source` (+`syntax`), `run` | the handle, and everything needed to speak to it |
| `list_worlds` | – | the worlds this server has open |
| `world_status` | `world` | cycle, status, how many fluents hold, what was refused |
| `close_world` | `world` | forgets an owned world |
| `list_live` / `attach_live` | – / `live` | the running live sessions, and a handle on one |

`open_world` is the tool that matters most, because its reply gives the agent
its whole vocabulary:

```json
{"world": "w1-1de44f", "cycle": 2, "status": "running",
 "vocabulary": {"events": ["temperature(A)", "set_target(A)", "window(A)"],
                "actions": ["heat(A)", "warn(A)"],
                "fluents": ["heating(A)", "target(A)", "temperature(A)", "window_state(A)"]},
 "constraints": [{"reads": "never heat(on) while window_state(open)",
                  "at": "thermostat.lps:46"}],
 "state": ["target(21)", "heating(off)", "window_state(shut)", "temperature(20)"]}
```

An agent that reads that reply cannot invent an event the program has never
heard of, and knows before it starts which rule is going to stop it.

### The guardrail

| Tool | Arguments | Reply |
|---|---|---|
| `propose_action` | `world`, `action`, `cycles` | `permitted`, `refused_by` (constraint, its English reading, its line, and the conditions that hold), `why_not`, and — when permitted — the `consequences` of doing it |
| `may` | `world`, `candidates`, `limit` | one row per action: permitted, refused, or *some instances*, with the refused instances named |

`may` with no candidates tests every action the program declares. An action
with variables in it comes back as `"permitted": "some instances"` with the
instances a constraint refuses — `heat(A)` is fine, `heat(on)` is not, and
that is a more useful answer than either "yes" or "no".

The check works the program's constraints out once, with the action put into
them, against the state the world is actually in. The check is not a run:
nothing is committed, and no cycle passes. The answer is the same one the
engine gives when the action is really attempted — `observe` the action and it
is refused, with the same constraint named.

### Looking ahead

| Tool | Arguments | Reply |
|---|---|---|
| `simulate` | `world`, `events` (`"term"` or `{event, after}`), `cycles` | the timeline of the copy, what happened each cycle, what was refused, what was violated, and the state it ends in |
| `what_would_violate` | `world`, `candidates`, `cycles` | per candidate: *refused by a constraint*, *leads to a violation*, or *nothing breaks* |
| `plan` | `world`, `cycles` | the actions this world will take next if nothing else happens — for a program in planning mode, the plan the planner found |

### Reading the run

| Tool | Arguments | Reply |
|---|---|---|
| `state` | `world`, `at`, `match` | what holds now, or at a past cycle |
| `observe` | `world`, `events`, `cycles` | **advances the world**; what changed, what the program did, whether a constraint refused the event |
| `timeline` | `world` | each fluent's intervals, the events and composites per cycle, everything refused |
| `changes` | `world`, `cycle` | what was initiated, terminated and updated, each with the event that caused it and the law's line — the *cause_of* question |
| `explain` | `world`, `question` \| `kind`+`what`+`at` | the five question forms, in English |
| `find_first` | `world`, `holds` \| `happened` | the first cycle something held or happened |
| `obligations` | `world` | the goals still outstanding |

The five question forms `explain` takes are the engine's own:
`why(happened(A), T)`, `why(holds(F), T)`, `why(stopped(F), T)`,
`why_not(happened(A), T)`, `why_not(holds(F), T)`.

## Prompts

| Prompt | Arguments | What it sets up |
|---|---|---|
| `act_within_the_rules` | `program` | open a world, speak only its vocabulary, check with `propose_action` before acting, explain afterwards, never assert the state from memory |
| `watch_a_live_run` | `live` | attach to a running session, monitor it, warn about what is about to go wrong, and do not drive it |

## Resources

| URI | Content |
|---|---|
| `lps://docs/language` | the [LPS language reference](../reference/lps.md) |
| `lps://docs/le-for-lps` | [Logical English for LPS](../reference/le-for-lps.md) |

## Protocol details

- `initialize` replies protocol version `2024-11-05`, capabilities `tools`,
  `prompts` and `resources`, and server name `LPS2 MCP Server`.
- A tool's result is its JSON reply, carried as the text of a single `text`
  content item. A reply that has an `error` field also sets `isError: true`.
- The server acts on notifications, which are messages with no `id`, and sends
  no reply to them.
- An unknown method gives the JSON-RPC code `-32601`, a message with no method
  gives `-32600`, and a tool that raises an exception gives `-32603`. A tool
  that simply cannot answer replies with `error` rather than failing the call,
  because an agent can read an error and act on it.
- When a model sends a tool name with rubbish stuck on the end
  (`observe<|channel|>…`), the server cuts the name at the `<`.

Tests: `tools/mcp_test.pl`
(`./myswipl.sh -q -g "consult('tools/mcp_test.pl')" -g "mcp_test:main" -t halt`).

## What this is not

- **Not a way to edit programs.** What MCP offers here is a way to run
  programs and to put questions to them. Writing a program is the IDE
  assistant's job.
- **Not a way of deciding who is allowed in.** The server checks program text
  that arrives in a request (`open_world` with `source`) against the sandbox
  rules on this door, just as it does on `/lpsapi`. The check is on unless
  `LPS_SANDBOX=0` declares the installation trusted, and a program that
  reaches out to the machine is refused, with the reasons given. The server
  does not check a program it ships itself, for the same reason the command
  line does not check a file of your own. *Who* may open a world at all is a
  separate question, and one for `LPS_TOKEN`.
- **Not shared with the IDE's sessions.** A world opened over MCP and a
  session opened in the IDE are two separate things. The one meeting point is
  a *live* session, which `attach_live` reads.

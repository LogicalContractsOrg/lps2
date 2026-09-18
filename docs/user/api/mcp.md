# LPS over MCP: a world an agent can ask

*Kind: reference · Audience: developers · Status: current (2026-09-18)*

The LPS2 server speaks the [Model Context Protocol](https://modelcontextprotocol.io)
(`src/edges/lps_mcp.pl`), so a language model — Claude Desktop, Claude Code,
opencode, or anything else that speaks MCP — can open a program as a **world**,
watch it, ask whether an action is allowed *before* taking it, look ahead at
what would follow, and ask why what happened happened.

This is a different offer from [Logical English over MCP](https://le2.logicalcontracts.com/docs/user/api/mcp),
and the two compose. LE answers *what follows from these facts*. LPS answers
*what happens next, what is permitted now, and what must never become true*.

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
cannot solve from its own weights: it does not know what is true now, it
cannot reliably work out the consequences of a sequence of actions, and it has
no way to be *stopped* by a rule rather than merely reminded of one.

An LPS program answers all three, because it is a state machine with laws:

| The agent's question | The tool | What answers it |
|---|---|---|
| What is true now? | `state`, `timeline` | the current state of the run, not a recollection |
| May I do this? | `propose_action`, `may` | the program's integrity constraints, evaluated against the state the world is actually in |
| What happens if I do? | `simulate`, `what_would_violate`, `plan` | a run on a copy of the world |
| What just happened, and why? | `explain`, `changes`, `find_first` | the recorded trace, with the law and the line that caused each change |
| What do I still owe? | `obligations` | the goals reactive rules created and nothing has discharged |

The guardrail is the point. `propose_action` does not ask the model to be
careful; it asks the engine, and the engine answers with the constraint that
refuses and the conditions that make it apply:

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

- **STDIO**: `./lps mcp` — one JSON-RPC message per line on standard input,
  one reply per line on standard output. Run it from the repository root: the
  examples and documents are read by relative paths.
- **HTTP**: `POST /mcp` on the IDE server (`./lps ide`, default port 3060),
  one JSON-RPC message per request. `GET /mcp` answers `405`: server-sent
  events are not implemented.

A server started with `LPS_TOKEN` takes it on the MCP endpoint as
`Authorization: Bearer <token>` or as `?token=` on the URL, because an MCP
client has nowhere to put the `token` field that `/lpsapi` operations use.

With a Logical English checkout (`LPS_LE2_LIB=<path to LogicalEnglish2>`) the
server also opens `.le` programs — the LE-for-LPS surface language, and with
it the migrated twins of Daml, Solidity and Drools programs.

## Client setup

Claude Desktop, `claude_desktop_config.json` — a local STDIO server:

```json
{
  "mcpServers": {
    "lps": { "command": "/path/to/lps2/lps", "args": ["mcp"] }
  }
}
```

or a running server through the `mcp-remote` bridge:

```json
{
  "mcpServers": {
    "lps": { "command": "npx", "args": ["mcp-remote", "http://localhost:3060/mcp"] }
  }
}
```

Claude Code, from the repository root:

```bash
claude mcp add lps -- ./lps mcp
claude mcp add lps -- npx mcp-remote http://localhost:3060/mcp
```

## Worlds

MCP conversations are not sessions, so the server hands out explicit handles.
A **world** is either

- **owned** — a session this server created with `open_world` and advances
  when you call `observe`; or
- **attached** — a read-through handle on a *live* session somebody else is
  driving (`list_live`, `attach_live`). Every reading tool works the same on
  it; `observe` sends the events to its driver instead of stepping it.

Two rules hold for every tool:

1. **Asking is free.** `propose_action`, `may`, `simulate`,
   `what_would_violate` and `plan` run on a copy. The world's cycle is the
   same after the call as before it, and each reply says so.
2. **Acting is explicit.** Only `observe` advances an owned world.

A world is a term in this process's memory, and its handle is tagged with the
process (`w3-1de44f`): a handle from another process is refused rather than
mistaken for a local one.

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

`open_world` is the one that matters, because its reply is the agent's whole
vocabulary:

```json
{"world": "w1-1de44f", "cycle": 2, "status": "running",
 "vocabulary": {"events": ["temperature(A)", "set_target(A)", "window(A)"],
                "actions": ["heat(A)", "warn(A)"],
                "fluents": ["heating(A)", "target(A)", "temperature(A)", "window_state(A)"]},
 "constraints": [{"reads": "never heat(on) while window_state(open)",
                  "at": "thermostat.lps:46"}],
 "state": ["target(21)", "heating(off)", "window_state(shut)", "temperature(20)"]}
```

An agent that reads this cannot invent an event the program has never heard
of, and knows before it starts which rule is going to stop it.

### The guardrail

| Tool | Arguments | Reply |
|---|---|---|
| `propose_action` | `world`, `action`, `cycles` | `permitted`, `refused_by` (constraint, its English reading, its line, and the conditions that hold), `why_not`, and — when permitted — the `consequences` of doing it |
| `may` | `world`, `candidates`, `limit` | one row per action: permitted, refused, or *some instances*, with the refused instances named |

`may` with no candidates tests every action the program declares. An action
with variables in it comes back as `"permitted": "some instances"` with the
instances a constraint refuses — `heat(A)` is fine, `heat(on)` is not, and
that is a more useful answer than either "yes" or "no".

The check is one evaluation of the program's constraints with the action
unified into them, in the state the world is in. It is not a run: nothing is
committed, no cycle passes, and the answer is the same one the engine gives
when the action is actually attempted — `observe` it and it is refused, with
the same constraint named.

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
- A tool's result is its JSON reply as the text of one `text` content item; a
  reply with an `error` field also sets `isError: true`.
- Notifications (messages without `id`) are acted on and not answered.
- An unknown method is JSON-RPC `-32601`; a message with no method, `-32600`;
  a tool that throws, `-32603`. A tool that cannot answer replies `error`
  rather than failing the call, because an agent can read an error.
- A tool name with trailing junk from a model (`observe<|channel|>…`) is cut
  at the `<`.

Tests: `tools/mcp_test.pl`
(`./myswipl.sh -q -g "consult('tools/mcp_test.pl')" -g "mcp_test:main" -t halt`).

## What this is not

- **Not a way to edit programs.** The MCP surface runs and questions
  programs; writing them is the IDE's assistant.
- **Not an authorisation boundary.** Program text that arrives in a request
  (`open_world` with `source`) is checked against the sandbox policy on this
  door, as it is on `/lpsapi` — the check is on unless `LPS_SANDBOX=0` says the
  deployment is trusted, and a program that reaches the machine is refused with
  its diagnostics. A program the server itself ships is not checked, for the
  same reason the CLI does not check your own file. *Who* may open a world is a
  separate question, and `LPS_TOKEN`'s.
- **Not shared with the IDE's sessions.** A world opened over MCP and a
  session opened in the IDE are separate; the meeting point is a *live*
  session, which `attach_live` reads.

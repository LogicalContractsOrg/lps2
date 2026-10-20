# LPS over MCP: a world an agent can ask

*Kind: reference · Audience: developers · Status: current (2026-09-18)*

The LPS2 server uses MCP, the
[Model Context Protocol](https://modelcontextprotocol.io). MCP is the agreed method
that a language model uses to call an outside program
(`src/edges/lps_mcp.pl`). Thus a language model can use an LPS (Logic Production
System) program. Examples of such language models are Claude Desktop, Claude Code,
opencode, or any other program that uses MCP. The language model can open the LPS
program as a **world**. A world is a running copy of the program, with its own state.
The language model can then do these things:

- Monitor that world.
- Ask if an action is permitted *before* it does the action.
- Look forward and see what will follow.
- Ask why something happened.

LPS gives a different thing from
[Logical English over MCP](https://le2.logicalcontracts.com/docs/user/api/mcp), and the
two work together. LE (Logical English) tells you *what follows from these facts*. LPS
tells you *what happens next, what is permitted now, and what must never become true*.

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

An agent is a language model that does actions for a person. Sometimes a language
model must act in a world that has rules. Then the model has three problems that it
cannot solve with only the data that it learned:

- The model does not know what is true now.
- The model cannot calculate correctly what follows from a sequence of actions.
- No rule can *stop* the model. A rule can only remind the model.

An LPS program solves all three problems. An LPS program is a machine that keeps a
state. The program changes that state only as its rules (its laws) say:

| The agent's question | The tool | What answers it |
|---|---|---|
| What is true now? | `state`, `timeline` | the current state of the run, not a memory of the model |
| May I do this? | `propose_action`, `may` | the integrity constraints of the program, which the engine examines against the real state of the world |
| What happens if I do? | `simulate`, `what_would_violate`, `plan` | a run on a copy of the world |
| What just happened, and why? | `explain`, `changes`, `find_first` | the recorded trace, with the law and the line that caused each change |
| What do I still owe? | `obligations` | the goals that reactive rules made and that nothing has completed |

An integrity constraint is a rule that says what must never become true. A reactive
rule is a rule that makes a goal when something happens. The engine is the part of
LPS that runs the program.

The guardrail is the most important part. A guardrail is a barrier that stops an
action. `propose_action` does not ask the model to be careful. `propose_action` asks
the engine. The engine replies with the constraint that refuses the action. The reply
also gives the conditions that make the constraint apply:

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

A transport is the channel that carries the messages between the client and the
server. There are two transports:

- **STDIO**, the plain input and output channels: `./lps mcp` reads one JSON-RPC
  message on each line of standard input. A JSON-RPC message is a request in the JSON
  text format. The command writes one reply on each line of standard output. Run the
  command from the top folder of the project. The server finds the examples and
  documents through paths that start from that folder.
- **HTTP**, through the web: send `POST /mcp` to the IDE server (`./lps ide`). The IDE
  is the editor of LPS2 in a web browser. The port is 3060 if you do not change it.
  Put one JSON-RPC message in each request. `GET /mcp` replies `405`, because this
  server does not send a stream of events to the client.

You can start a server with `LPS_TOKEN`. Such a server accepts the token at the MCP
address in one of two forms. The first form is `Authorization: Bearer <token>`. The
second form is `?token=` on the URL. The `/lpsapi` operations use a `token` field. But
an MCP client has no place for that field. Thus the token goes in one of those two
places.

The server can also open `.le` programs if a copy of Logical English is on the
machine (`LPS_LE2_LIB=<path to LogicalEnglish2>`). These programs are written in LE
for LPS. LE for LPS is the language that people read and write. These programs
include the twins that were migrated from Daml, Solidity and Drools programs. A twin
is a copy of a program from a different system, written again in LE for LPS.

## Client setup

Claude Desktop, `claude_desktop_config.json`, with a local STDIO server:

```json
{
  "mcpServers": {
    "lps": { "command": "/path/to/lps2/lps", "args": ["mcp"] }
  }
}
```

Or, for a server that already runs, use `mcp-remote`. `mcp-remote` is a small program
that sends the messages to the server:

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

An MCP conversation is not a session. Thus the server gives a handle with a name for
each world. A handle is a name that identifies one world. A **world** is one of two
things:

- **owned**: a session that this server made with `open_world`. The world moves
  forward when you call `observe`.
- **attached**: a handle that reads a *live* session. A different person or program
  controls that session (`list_live`, `attach_live`). Each tool that reads operates
  in the same way on an attached world. `observe` on an attached world sends the
  events to the controller of that session. `observe` does not move that session
  forward itself.

Two rules apply to all tools:

1. **Asking is free.** `propose_action`, `may`, `simulate`,
   `what_would_violate` and `plan` run on a copy. The cycle of the world is the same
   after the call as before the call. Each reply says this.
2. **Acting is explicit.** Only `observe` moves an owned world forward.

A world is in the memory of the server that runs it. The handle of a world has a mark
that identifies that server (`w3-1de44f`). Thus the server refuses a handle from a
different server. The server does not think that such a handle is one of its own.

## Tools

### Finding and opening

| Tool | Arguments | Reply |
|---|---|---|
| `list_programs` | `match` | `{programs: [{name, title}]}`: the examples that come with LPS2, the LE-for-LPS programs, and the migrated twins |
| `open_world` | `program` \| `source` (+`syntax`), `run` | the handle, and all the data that is necessary to speak to the world |
| `list_worlds` | – | the worlds that this server has open |
| `world_status` | `world` | the cycle, the status, the number of fluents that are true, and what the engine refused |
| `close_world` | `world` | removes an owned world from memory |
| `list_live` / `attach_live` | – / `live` | the live sessions that run now, and a handle on one of them |

A fluent is a fact that can change from one cycle to the next. `open_world` is the
most important tool, because its reply gives the agent all of its vocabulary:

```json
{"world": "w1-1de44f", "cycle": 2, "status": "running",
 "vocabulary": {"events": ["temperature(A)", "set_target(A)", "window(A)"],
                "actions": ["heat(A)", "warn(A)"],
                "fluents": ["heating(A)", "target(A)", "temperature(A)", "window_state(A)"]},
 "constraints": [{"reads": "never heat(on) while window_state(open)",
                  "at": "thermostat.lps:46"}],
 "state": ["target(21)", "heating(off)", "window_state(shut)", "temperature(20)"]}
```

An agent that reads that reply cannot invent an event that the program does not know.
The agent also knows, before it starts, which rule will stop it.

### The guardrail

| Tool | Arguments | Reply |
|---|---|---|
| `propose_action` | `world`, `action`, `cycles` | `permitted`; `refused_by` (the constraint, its English reading, its line, and the conditions that are true); `why_not`; and, when the action is permitted, the `consequences` of the action |
| `may` | `world`, `candidates`, `limit` | one row for each action: permitted, refused, or *some instances*, with the names of the refused instances |

If you give `may` no candidates, `may` tests all the actions that the program
declares. An action can contain variables. A variable is a part of the action that
can have different values. Such an action comes back as
`"permitted": "some instances"`, with the instances that a constraint refuses. For
example, `heat(A)` is permitted, but `heat(on)` is not permitted. That answer is more
useful than "yes" or "no".

The check calculates the constraints of the program one time. The check puts the
action into the constraints and uses the real state of the world. The check is not a
run: nothing changes, and no cycle passes. The answer is the same as the answer of the
engine when the action really occurs. If you `observe` the action, the engine refuses
it and names the same constraint.

### Looking ahead

| Tool | Arguments | Reply |
|---|---|---|
| `simulate` | `world`, `events` (`"term"` or `{event, after}`), `cycles` | the timeline of the copy, what happened in each cycle, what the engine refused, what broke a constraint, and the last state |
| `what_would_violate` | `world`, `candidates`, `cycles` | for each candidate: *refused by a constraint*, *leads to a violation*, or *nothing breaks* |
| `plan` | `world`, `cycles` | the actions that this world will do next if nothing else happens. For a program in planning mode, the plan that the planner found |

### Reading the run

| Tool | Arguments | Reply |
|---|---|---|
| `state` | `world`, `at`, `match` | what is true now, or at a past cycle |
| `observe` | `world`, `events`, `cycles` | **moves the world forward**; tells what changed, what the program did, and if a constraint refused the event |
| `timeline` | `world` | the intervals of each fluent, the events and composites in each cycle, and all that the engine refused |
| `changes` | `world`, `cycle` | what was initiated, terminated and updated, each with the event that caused it and the line of the law. This is the *cause_of* question |
| `explain` | `world`, `question` \| `kind`+`what`+`at` | the five question forms, in English |
| `find_first` | `world`, `holds` \| `happened` | the first cycle where something was true or happened |
| `obligations` | `world` | the goals that are not complete |

`explain` accepts five question forms. These forms are the forms of the engine:
`why(happened(A), T)`, `why(holds(F), T)`, `why(stopped(F), T)`,
`why_not(happened(A), T)`, `why_not(holds(F), T)`.

## Prompts

A prompt is a set of instructions that the server gives to the language model.

| Prompt | Arguments | What it sets up |
|---|---|---|
| `act_within_the_rules` | `program` | open a world, use only its vocabulary, check with `propose_action` before an action, explain after the action, never say what the state is from memory |
| `watch_a_live_run` | `live` | attach to a session that runs, monitor it, give a warning about a problem that will occur soon, and do not control the session |

## Resources

A resource is a document that the server gives to the client.

| URI | Content |
|---|---|
| `lps://docs/language` | the [LPS language reference](../reference/lps.md) |
| `lps://docs/le-for-lps` | [Logical English for LPS](../reference/le-for-lps.md) |

## Protocol details

- `initialize` replies with the protocol version `2024-11-05`, the capabilities
  `tools`, `prompts` and `resources`, and the server name `LPS2 MCP Server`.
- The result of a tool is its JSON reply. The text of one `text` content item
  contains that reply. A reply that has an `error` field also sets `isError: true`.
- A notification is a message that has no `id`. The server does the notification,
  but it does not reply.
- An unknown method gives the JSON-RPC code `-32601`. A message with no method gives
  `-32600`. A tool that raises an exception gives `-32603`. Sometimes a tool cannot
  answer. Then the tool replies with `error`, and the call does not fail. The reason
  is that an agent can read an error and act on it.
- Sometimes a model sends a tool name with unwanted text at the end
  (`observe<|channel|>…`). The server then cuts the name at the `<`.

Tests: `tools/mcp_test.pl`
(`./myswipl.sh -q -g "consult('tools/mcp_test.pl')" -g "mcp_test:main" -t halt`).

## What this is not

- **Not a way to edit programs.** Here, MCP gives a way to run programs and to ask
  them questions. The IDE assistant writes programs.
- **Not a way to decide who can come in.** The server examines program text that comes
  in a request (`open_world` with `source`). The server uses the sandbox rules of this
  entry point for this check, the same as on `/lpsapi`. The sandbox rules stop a
  program that does dangerous actions on the computer. The check is on, unless
  `LPS_SANDBOX=0` declares the installation trusted. The server refuses a program that
  tries to use the computer outside LPS, and it gives the reasons. The server does
  not check a program that comes with the server. The command line does not check
  your own file, for the same reason. *Who* can open a world is a different question.
  `LPS_TOKEN` controls that question.
- **Not shared with the IDE's sessions.** A world that you open through MCP and a
  session that you open in the IDE are two different things. They meet at one point
  only: a *live* session, which `attach_live` reads.

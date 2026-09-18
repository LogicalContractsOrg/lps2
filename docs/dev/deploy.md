# Deploying LPS2

*Kind: operations · Audience: developers, operators · Status: current (2026-09-15)*

One container: the engine, the `/lpsapi` endpoint and the web IDE, served by
one SWI-Prolog process on one port.

**The engine has no build step; the IDE does** (since M14). The `Dockerfile` is
two stages: a Node stage that bundles Monaco, Konva, three.js and dagre into
`src/ide/dist/`, and the SWI-Prolog stage that serves them. Node appears in the
build and not in the image, so what is deployed is still one Prolog process, and
`src/ide/dist/` is a build artefact rather than something checked in.

Building the UI outside Docker:

```sh
npm --prefix ui install
npm --prefix ui run build      # or `run watch` while developing
```

```sh
tools/vendor_le2.sh /path/to/LogicalEnglish2   # optional: Logical English
docker build -t lps2 .
docker run -p 3060:3060 lps2            # http://localhost:3060/
```

## fly.io

```sh
fly launch --no-deploy                  # once, if the app does not exist
fly secrets set LPS_TOKEN=$(openssl rand -hex 24)
./buildPush.sh                          # vendors LE2, builds locally, deploys
```

`buildPush.sh` builds locally rather than on fly's remote builder, for the same
reason LE2's does: the build stamps the image with the git revision it came
from, and a remote builder would stamp whatever it happened to fetch. What is
deployed is then the image that was actually tested.

On a Mac the Docker socket usually needs pointing at first:

```sh
export DOCKER_HOST=unix:///Users/$USER/.docker/run/docker.sock
```

### `force_https`, and a page opened at `http://`

`fly.toml` sets `force_https = true`, so fly answers an `http://` address with
a 301 to the `https://` one and the app never sees the request. That is right,
and it has one consequence the IDE has to handle itself: a browser that is
*already on* the `http://` page follows that redirect on a GET but turns a POST
into a GET, which `/lpsapi` answers with 405 — every operation fails while the
editor looks fine — and Monaco's worker becomes a cross-origin import that no
CORS header allows. So `ui/src/api.js` reads the origin that fetch reports coming
back and moves the page there, once. Nothing needs configuring; it is here
because the symptom (405 on every operation, "Failed to fetch dynamically
imported module: …/editor.worker.js") says nothing about its cause.

### One machine, and one only

`buildPush.sh` deploys with `--ha=false`, and the app is pinned to a single
machine:

```sh
fly scale count 1
fly status                              # check it after any manual deploy
```

This is not thrift, it is correctness. Every handle the server hands out — a
compiled program, a run session, an assistant job, a live session — names a term
in the memory of the process that minted it. There is no shared store and no
sticky routing, so a second machine does not share the load; it takes half the
requests to a process that has never heard of the thing they name.

What that looks like from a browser, because it took a while to recognise: you
run a program, and the 2D pane says `error(lps_no_such_session(s1), _)`. Or you
press *Animate in 2D* and the assistant replies `no such job` — the job is
running perfectly well on the other machine, and nobody is listening to it.
Intermittent, absent from the logs (nothing failed; the request was answered
correctly by a machine that genuinely had no such session), and not reproducible
whenever only one machine happens to be awake — which, with
`auto_stop_machines = 'stop'`, is most of the time.

`fly deploy` creates two machines by default, for availability. For this app
that default is simply wrong, and `fly launch` will reintroduce it given the
chance.

Ids carry a per-process tag — `s1-cd863e`, not `s1` (`src/edges/lps_ids.pl`) —
so that if the fleet ever grows again the symptom stays honest. Untagged, both
machines mint `s1`, and the *worse* outcome is the one where the other machine
does have an `s1`: no error at all, just somebody else's session answering.
The tag is not a capability and does not authorise anything; that is
`LPS_TOKEN`'s job.

### Scaling, if the one machine stops being enough

Written down because the question comes back, and because the obvious answer —
add a machine — is the wrong one here for reasons that are not obvious.

**Scale up before you scale out.** An LPS run is CPU-bound and shares nothing: a
planner searching is one thread burning one core, and two users doing it are two
independent computations. `cpus = 2`, or a `performance-1x` VM, therefore buys
the same capacity as a second machine with none of the routing problem, because
there is no routing problem — the state is all in the one process either way.
Memory is the other axis: sessions and live sessions are retained traces, and
`keep_cycles/1` in `src/edges/lps_live.pl` bounds each one, but nothing bounds
how many there are.

**Scaling out needs `fly-replay`.** Should a second machine ever be wanted, the
mechanism is fly's dynamic request routing rather than anything cookie-shaped:
a response carrying `fly-replay: instance=<machine-id>` is re-delivered by the
proxy to that machine, transparently to the browser. The routing key already
exists — it is the per-process tag on every id (`src/edges/lps_ids.pl`), which
would become `FLY_MACHINE_ID` where one is set:

- `server_nonce/1` returns the machine id on fly, and stays random elsewhere, so
  a laptop behaves exactly as it does now.
- The four places that resolve an id — `program_of/2`, `session_of/3`,
  `live_id/2`, `assistant_status/2` — split the tag off it. A tag naming another
  machine throws `replay_to(M)` instead of failing, and the `lpsapi` handler
  turns that into the header.
- `fallback=prefer_self`, so an id whose machine is gone comes back to us and
  gets the honest "no such session" rather than hanging.
- `compile` carries no id, lands anywhere, and is therefore where the balancing
  happens: a user is pinned by their first compile and stays put.

That much is around forty lines. What makes it more than a weekend is the tax:
**a replay is an extra proxy hop, and it does not go away.** Half the users are
pinned to the machine not receiving their requests, and the IDE polls hard — a
running live animation is several requests a second, every one of them replayed.
Making that acceptable means the client storing the machine id and sending it
back as `Fly-Force-Instance-Id`, so the common path routes directly and
`fly-replay` is only the net. Which puts a piece of the routing contract in the
browser, where forgetting it on one newly added API call reintroduces exactly
the bug this section exists to explain — intermittently, and invisibly in the
logs.

**And it is not high availability.** A machine dying still takes its sessions,
its assistant jobs and its live animations with it; the users on it get errors
and reload. Two machines buy throughput, not continuity. Continuity needs the
session state out of the process — a real project, and a different one.

Note also that `auto_stop_machines = 'stop'` and a live session are in tension,
and this is true at one machine as much as at two. The driver is a thread, not
a request, and fly counts *requests* — so a live session nobody is watching does
not register as activity at all, and the machine stops with the session still
running on it. What keeps a machine awake is the browser polling `live_status`,
which is to say the panel being open. A session left to run unattended is a
session that will be collected.

## Configuration

| variable | meaning |
|---|---|
| `LPS_PORT` | the port to serve on. Default 3060. |
| `LPS_TOKEN` | required in every request body as `"token"`. **Set it.** |
| `LPS_ORIGIN` | the origin allowed to call `/lpsapi` cross-site. Default `*`. |
| `LPS_LE2_LIB` | an LE2 checkout, **loaded into this process** — what the image sets, pointing at the vendored copy. Turns Logical English on. |
| `LPS_LE2_URL` | an LE2 `/leapi` endpoint instead. Used when there is no `LIB`. |
| `LPS_LE2_DIR` | an LE2 checkout; in-process by default, subprocess with `LPS_LE2_SUBPROCESS=1`. |
| `LPS_LE2_NETWORK` | let a `.le` document's URL-valued resources be fetched. Off: opening somebody's file should not make requests on their behalf. |
| `LPS_SANDBOX` | `0` turns the server's check on a program's Prolog off; `1` turns the CLI's on. |
| `LPS_SENTRY_DSN`, `LPS_CLOUDFLARE_ANALYTICS_TOKEN` (and `LPS_SENTRY_ENVIRONMENT`, `LPS_SENTRY_RELEASE`) | error reports to Sentry, with its feedback form, and Cloudflare Web Analytics. Off unless set; set as fly secrets on the deployed app only — [`telemetry.md`](telemetry.md). |

With none of the three `LE2` variables naming something real, Logical English is
absent and everything else is unchanged — see [an image without
it](#an-image-without-it).

### The sandbox, and what the token is still for

`/lpsapi compile` takes a program and runs it, and an LPS program may contain
ordinary Prolog — that is the language, not a hole in it. `shell/1` is ordinary
Prolog.

So **the server checks the Prolog in a program before running it**, with SWI's
own `library(sandbox)` — the mechanism SWISH exposes to the public internet.
The check is on the predicates *the program* defines; the engine's own code is
not its business. It runs once at compile time rather than on every call,
because `safe_goal/1` follows the call graph (~230 µs a predicate, against
thousands of calls a cycle) — and following the call graph is also what makes
one check enough: asking about every predicate a program defines covers every
goal any of them can reach.

Two escapes from a compile-time check are closed by refusing the *construction*
rather than the call: a goal built at run time cannot be proved safe, so a
program containing one is refused with the goal named; and SWI's sandbox
refuses `assertz/1` of any clause with a body. `tools/sandbox_test.pl` holds
both properties — the ordinary vocabulary keeps working, the machine-reaching
one does not — and runs the whole shipped corpus through it: **170 of 172
programs pass**. The two that do not are honest refusals: one reads stdin, one
calls a REST client.

| where | default | why |
|---|---|---|
| the HTTP endpoint | **on** | it compiles programs from strangers |
| the CLI | off | your file, your machine — `--sandbox` turns it on |

`LPS_SANDBOX=0` turns the server's off for a deployment that trusts its callers;
`LPS_SANDBOX=1` turns the CLI's on.

**This changes what the token is for, and not whether you want one.** A
sandboxed server is no longer an open Prolog interpreter, so `LPS_TOKEN` stops
being the only thing between a stranger and the machine. What it still buys is
*whose CPU this is*: the sandbox is not a resource limit, a program can loop
inside a single cycle, and an untokened public deployment is one anybody may
keep busy. Choose accordingly — a demo server for a class can reasonably run
without one now; a machine you care about should not.

An untokened deployment reachable from the internet was, before this, an open
Prolog interpreter. `./lps ide` prints `no token: every request is accepted` when
there is none, and `buildPush.sh` warns before deploying without one, so the
state you are in is never a surprise; neither of them refuses, because a
tokenless server on a laptop is exactly what you want while developing.

**The browser needs it too.** Everything the IDE does is a `/lpsapi` call, so
on a tokened server a browser without the token can edit text and nothing else
— no examples, no analysis, no runs. Three ways in, in the order they are
convenient:

- **A link that carries it**: `https://your-app/ide?token=…`. The IDE stores
  it and takes it back out of the address bar, so it is not left in the history
  or copied along with the next share link.
- **Misc ▸ Server token…**, which keeps it in that browser's local storage.
- Nothing: the first refused operation opens that dialog itself, saying which
  operation was refused and why.

`GET /lpsapi/status` answers `{ok, token_required, logical_english}` without a
token, which is how the IDE knows to ask before its first request rather than
after its first failure. It is deliberately unauthenticated and carries nothing
else: that a server requires a token is the first thing a refused client learns
anyway.

## Logical English, in the same process

LPS2 does not parse Logical English; LE2 does, and `docs/dev/le-lps-interface.md` is
the contract between them. Since M8f the way LPS2 *reaches* LE2 is by loading
its language service — one module, `le_service.pl` — into its own image. So a
deployment that runs `.le` programs is **one app**, and the whole of the
configuration is a directory in the image.

### What to do

```sh
tools/vendor_le2.sh /path/to/LogicalEnglish2
./buildPush.sh
```

`buildPush.sh` does the first step itself when it can find a checkout
(`LPS_LE2_DIR`, or `/LogicalEnglish2`), so in practice it is one command.

`tools/vendor_le2.sh` copies a **minimal** Logical English into `vendor/le2/`:
the language service and its keyword tables, about 800 kB, and not LE2's editor
or its web API. Which files those are is not a list anybody maintains — the
script loads `le_service.pl` and asks the loader what it consulted, so the set
cannot go stale when LE2 moves a module. It then checks that the copy loads
from its new home, because it is exactly the sort of thing that only fails
later.

`vendor/le2/` is gitignored — a copy of another repository does not belong in
this one's history — so **re-run the script when the LE2 checkout moves**. The
image records where the copy came from in `vendor/le2/VENDORED.txt`, including
the LE2 revision.

`fly.toml` already sets `LPS_LE2_LIB=/app/vendor/le2`, and the Dockerfile fails
the *build* rather than a user's first `.le` if what was vendored does not load.

### What it costs

Nothing until a `.le` is opened: the library is loaded lazily, on the first
document. After that, about **10 MB of RSS and 1.5 s once**; a document then
compiles in about **0.2 s**, which is the whole reason for doing it this way
rather than starting a process per document. The fly machine's 1 GB is
unaffected in any way that matters.

`LPS_LE2_NETWORK` is off: a `.le` document may name a resource by URL, and a
server that fetched one would be making an outbound request on an author's
behalf because somebody opened a file. Set it to `1` if you mean it.

### An image without it

Building without the vendoring step is a supported state, not a broken one.
`vendor/le2/` is then empty, `lps_le_available/1` reads that as "no LE2", and
Logical English is **absent**: `.le` files open, say which variable to set, and
nothing else in the IDE, the CLI or the API changes. It never guesses — a `.le`
compiled by the wrong LE2 is a program whose meaning nobody stated.

---

## The other arrangement: two apps over HTTP

The original deployment shape, still supported and still the right one when LE2
is a service somebody else runs. It needs no vendoring: point LPS2 at an
endpoint and it uses that instead.

```sh
fly secrets set LPS_LE2_URL=https://logicalenglish2.fly.dev/leapi
```

`LPS_LE2_LIB` wins when both are set, so an image with a vendored copy has to
have that copy removed — or the variable cleared — before the URL is consulted.

In this arrangement the browser talks to both:

```
   browser
      │  the editor holds two base URLs and picks by language mode
      ├──── POST /leapi   ────▶  logicalenglish2.fly.dev   (port 3050)
      │        {operation: "getLps", le: "<document>"}
      │     ◀── {lps, provenance, issues}
      │
      └──── POST /lpsapi  ────▶  lps2.fly.dev              (port 3060)
               {operation: "compile", syntax: "internal",
                source: <lps>, provenance: <provenance>}
```

**Two apps and no proxy**, deliberately (`docs/project/plans/le_lps_design.md` §3). Proxying
LPS operations through `/leapi` would couple the two deployments and put LE2
in the business of forwarding an operation set it does not understand — and
the set grows: `compile`, `session_new`, `observe`, `step`, `run`, `state`,
`fork`, `discard`, `trace`, `dump`, `analyse`, `explain`, `timeline`,
`changes`, `scene`, `automaton`.

Three consequences worth knowing before you deploy them together:

- **Both must be reachable from the browser**, so both need `force_https` and
  a public hostname. Cross-origin requests from the LE2 editor to `/lpsapi`
  need the LPS app to allow that origin.
- **Neither is the other's health check.** They start, stop and scale to zero
  independently (`auto_stop_machines = 'stop'` in both), so the first request
  after an idle period wakes only the app it is addressed to. An editor
  keystroke that needs both will wake both, one after the other.
- **The tokens are separate.** `LPS_TOKEN` protects `/lpsapi`; LE2's own auth
  protects `/leapi`. Setting one does nothing for the other.

### Side by side on one development machine

Only needed to work on *LE2's* editor: to work on Logical English **in LPS2's**
IDE, start one server with `LPS_LE2_LIB` and there is no second one.

Two servers, two ports, two checkouts, and **no shared directory** — they talk
over HTTP and nothing else. Start LE2 first:

```sh
cd /path/to/LogicalEnglish2
./myswipl.sh -q -g "use_module(classic_web_api), start_api_server(3050)" \
             -g "thread_get_message(_)"
```

then LPS2, in its own checkout:

```sh
cd /path/to/lps2
./lps ide --port 3060
```

Now there are three URLs, and which one you open decides which editor you get:

| open this | you get | who compiles the LE |
|---|---|---|
| <http://localhost:3060/> | **LPS2's** editor. `.lps`, `.pl`, `.pddl`, `.drl` | — |
| <http://localhost:3050/editor/lps.html> | **LE2's** editor, its `lps` target mode | LE2 at :3050, run by LPS2 at :3060 |
| <http://localhost:3050/> | LE2's own editor, its usual targets | LE2 |

LE2's `editor/lps.html` defaults to `http://localhost:3060/lpsapi`, so on the
ports above it needs no configuration at all. To point it somewhere else, put
the URL in the query string:

```
http://localhost:3050/editor/lps.html?lpsapi=http://localhost:3099/lpsapi
```

and `?token=…` if that LPS2 was started with `LPS_TOKEN` set. Both are
remembered in the browser's local storage under `lps-lpsapi` and `lps-token`.

Three things go wrong here, all of them once:

- **CORS.** The page comes from :3050 and posts to :3060, which is
  cross-origin. LPS2 sends `Access-Control-Allow-Origin: *` unless `LPS_ORIGIN`
  says otherwise, so a laptop needs nothing; a deployment should set
  `LPS_ORIGIN` to the LE2 origin and `LPS_TOKEN` to something.
- **"LE missing_rules: the program contains only facts and no rules."** This is
  LE2's *verifier*, not a compilation error, and the program runs anyway. Its
  facts/rules heuristic counts Prolog clauses with bodies in the knowledge
  base's module; an LPS-target document asserts none, because its rules become
  `reactive_rule/2`, `updated/4` and `d_pre/1` facts handed over to LPS2.
  Harmless, and fixable only in LE2 (`le_verifier.pl`'s `facts_rules_ratio/2`
  should skip the check when the target language is `lps`).
- **Two engines, two idea of "compiled".** LE2's `compile & run` compiles with
  LE2 and runs with LPS2. If the run fails, the message comes from LPS2 and
  points at the *English* line through the provenance array — that is what
  `docs/dev/le-lps-interface.md` is for. If the *compile* fails, it is LE2's
  message and LPS2 never saw the document.

### The command line

For the CLI, point at a checkout and it is loaded into the process:

```sh
export LPS_LE2_DIR=/path/to/LogicalEnglish2
./lps run examples/le/goat.le
./lps dump foo.le --syntax legacy        # English in, LPS surface syntax out
```

`LPS_LE2_SUBPROCESS=1` brings back the older behaviour — LE2 in a child
SWI-Prolog — for whoever wants the isolation. It was the default because a
`.le` document can pull in arbitrary Prolog resources; it stopped being the
default because LE2's own loader asserts rather than consults, so loading a
document parses it and does not run it.

With nothing set, `./lps run foo.le` refuses rather than guessing.

## What is in the image, and why

| copied | why |
|---|---|
| `src/` | the engine, the syntax layer, the edges, the IDE page |
| `examples/` | LPS2's own examples, offered by the IDE's example picker |
| `legacy_lps1/` | not optional: the IDE offers its CLOUT_workshop programs, and ten corpus programs `:- include(system('date_utils.pl'))` |
| `conformance/`, `tools/` | so `./lps test` and the lint work in the container |
| `docs/` | so the deployed thing carries its own documentation |
| `vendor/` | a minimal Logical English, when `tools/vendor_le2.sh` put one there: LE2's language service and keyword tables, ~800 kB. Empty is a supported state |

`build/` is excluded — it is scratch: work directories, engine variants, run
logs, generated reports and IDE screenshots — and so, at **any depth**, is
`node_modules`. That `**/` matters: `.dockerignore` patterns are matched
against the root of the build context, so a bare `node_modules/` excludes only
the top-level one. With it missing, `ui/node_modules` (161 MB) and
`examples/agents/minecraft/node_modules` (918 MB) were both transferred to the daemon
and the second was copied into the image by `COPY examples/` — a gigabyte of
Node packages in an image that contains no Node, and about three minutes of
every build. The context is ~66 MB, most of it `legacy_lps1/`.

Excluding `ui/node_modules` is also a correctness fix rather than only a speed
one. The UI stage runs `npm install` and *then* `COPY ui/ ./`; with the host's
`node_modules` in the context, that copy lands a host-platform esbuild on top
of the one just installed, and an esbuild built for `darwin-arm64` does not run
in a `linux/amd64` image.

The build ends with

```dockerfile
RUN swipl -q -g "consult('src/lps.pl')" -g "halt(0)" -t "halt(1)"
```

so a program that does not load fails the *build* rather than the running
server — and, when something was vendored, with the same check on
`vendor/le2/le_service.pl`. A broken vendor directory that only shows up when a
user opens a `.le` is what that second line is there to prevent.

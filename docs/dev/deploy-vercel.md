# Deploying LPS2 as a static site (WebAssembly, Vercel)

*Kind: operations · Audience: developers, operators · Status: current (2026-09-20)*

There are two ways to deploy LPS2, and they are not versions of each other.

|  | **The server** ([`deploy.md`](deploy.md)) | **The browser** (`wasm/build.sh`) |
|---|---|---|
| What runs the engine | one SWI-Prolog process on fly.io | SWI-Prolog compiled to WebAssembly, in each visitor's tab |
| What the host does | runs a container | serves files |
| Programs and sessions live | in that one process's memory | in the tab that made them |
| Scaling | **one machine, and one only** — the reason is in [`deploy.md`](deploy.md#one-machine-and-one-only) | nothing to scale: every visitor brings an engine |
| The assistant | on a thread, streaming | in the request: same answers, no streaming, no *Stop* |
| Live sessions | yes | no (§ What is not there) |
| Logical English | `LPS_LE2_LIB`, in process | yes, when the build was made `--with-le` |
| Cost when nobody is using it | a machine that stops and starts | a static file bill |
| Privacy | the program is POSTed to the server | the program never leaves the machine |

Both run the same operations, because since this change they *are* the same
code: `src/edges/lps_api.pl` is the half of the old `lps_http.pl` with no HTTP
in it, and both deployments call its `handle/2`. The server reads a POST,
checks the token and writes the reply; the browser build
(`wasm/lps_wasm_app.pl`) reads a message from the page and answers it. An
operation is implemented once.

**Nothing here changes the fly.io deployment.** The `Dockerfile`, `fly.toml`
and `buildPush.sh` are untouched, and `wasm/` is not in the image.

This is not the same thing as **Deploy as WASM** in the IDE's Misc menu
(`src/edges/lps_wasm.pl`, M11), which writes a single self-contained page
carrying *one program* and the engine. That was the proof that the engine runs
in a browser; this is the IDE built on it.

---

## Build it

Prerequisites: SWI-Prolog (`./myswipl.sh` finds it), Node 18 or later, `curl`,
and — for the deploy — the [Vercel CLI](https://vercel.com/docs/cli)
(`npm i -g vercel`).

```sh
./wasm/build.sh                                 # → wasm/dist/
node wasm/runtime/serve.mjs wasm/dist 8080      # → http://localhost:8080/
```

`wasm/dist/` is the whole site: about 26 MB on disk, of which a visitor
downloads **about 2.6 MB compressed** before the first program compiles — the
SWI-Prolog runtime (0.8 MB of WebAssembly and 1.2 MB of its library) and one
payload file of 0.5 MB with LPS2's Prolog, the examples and the corpus. The
IDE's own bundle, Monaco, Konva, three.js and the documentation arrive as they
are needed, and the browser caches all of it.

Options:

| | |
|---|---|
| `--with-le` | include the vendored Logical English (`vendor/le2`), so that `.le` programs compile **in the page**. Run `tools/vendor_le2.sh /path/to/LogicalEnglish2` first |
| `--skip-ui` | reuse `src/ide/dist` as it stands, instead of `npm --prefix ui run build` |
| `--out DIR` | build somewhere other than `wasm/dist` |
| `--private` | allow a payload that carries private files (see below) |
| `--port N` | the port the build's own export server uses (default 3199) |

The build builds the IDE; takes the SWI-Prolog WebAssembly runtime from
`ui/static/swipl/` (the same copy M11's pages use) or npm; packs the payload;
**starts the real LPS2 server** and saves the pages it renders — the landing
page and one shell per document, each carrying its own `window.LPS_DOC` — as
static HTML; copies the IDE's files, the documents and their pictures;
installs the browser runtime and `config.js`; and writes `vercel.json`.

### Logical English in the browser

With `--with-le` the payload carries `vendor/le2`, and
`wasm/lps_wasm_app.pl` points `LPS_LE2_LIB` at it inside the virtual file
system. The in-process transport of
[`le-lps-interface.md`](le-lps-interface.md) §3.5 is the only one a browser
has — `LPS_LE2_URL` would be a cross-origin POST no LE2 server invites, and
`LPS_LE2_DIR` needs a process to start — and it works: a `.le` compiles, runs,
explains itself and can be played, with no server of any kind.

`vendor/le2` is a copy of *another* repository, made by `tools/vendor_le2.sh`
from whichever checkout was to hand. If that one had the private grammar
extensions linked in, they were copied too — so the build **refuses** to
publish a `vendor/le2` containing `le_extensions.pl` or `le_importers.pl`
unless `--private` is also given, and says which file stopped it. Re-vendor
from a checkout without them for a public site.

## Deploy it

```sh
cd wasm/dist
vercel deploy            # a preview URL
vercel deploy --prod     # the production domain
```

There is no build step and there must not be one: Vercel has no SWI-Prolog,
and `wasm/dist` is already the finished site. Deploying the directory itself
is Vercel's zero-configuration case — static files, plus `api/` as Serverless
Functions, plus the `vercel.json` the build wrote. (`--prebuilt` is a
different thing: it deploys a `.vercel/output` tree produced by
`vercel build`, which we have no use for.)

The first `vercel deploy` asks which project to attach to and writes
`.vercel/` into `wasm/dist`, which the next build removes; either answer
again, or keep the link:

```sh
cd wasm/dist && vercel link        # writes wasm/dist/.vercel/project.json
cp -r .vercel ../vercel-project    # keep it across builds
# next time:  cp -r ../vercel-project wasm/dist/.vercel
```

From CI, with SWI-Prolog available:

```yaml
- run: sudo apt-get install -y swi-prolog-nox
- run: ./wasm/build.sh
- run: npx vercel deploy --prod --token=${{ secrets.VERCEL_TOKEN }}
  working-directory: wasm/dist
```

### Other hosts

Nothing is Vercel-specific except `vercel.json`, whose rewrites the build also
writes out in English as `wasm/dist/STATIC-HOSTS.md`. Any static host will do;
without the rewrites the site still works, with `/ide.html` in the address bar
rather than `/ide`. One requirement, wherever it is: `payload.bin` must arrive
with its bytes intact — it is gzip, and the worker decompresses it itself when
the host has not.

## The environment: the proxy, and keys

A page may not fetch another origin unless that origin allows it, and a model
provider does not. An agent program that talks to a model
(`src/edges/lps_llm.pl`) therefore goes through a same-origin proxy, which the
build ships as a Vercel Function at `/api/proxy` (`wasm/api/proxy.js`): it
forwards only to hostnames on a list, adds the key from the environment, does
not follow redirects, and caps the body and the time.

```sh
vercel env add GROQ_API_KEY production      # or OPENAI_API_KEY, ANTHROPIC_API_KEY, …
vercel env add LPS_PROXY_ALLOW production   # optional: the hostnames, comma-separated
```

`LPS_PROXY_ALLOW` unset means the default list (the providers `lps_llm.pl`
knows); **empty means none**, which turns the outbound half off. To deploy
with no proxy at all, set `proxy: ''` in `wasm/dist/lps-wasm/config.js` and
delete `wasm/dist/api/`.

## What is in the payload

`wasm/pack.pl` decides. `examples/` is nearly a gigabyte — almost all of it
the Minecraft agent's `node_modules` and its texture packs — so the rule is a
short extension list (`.le .lps .pl .pddl .ni .drl .md .txt`) and the same
directories the IDE's own example tree skips (`node_modules`, `sources`,
`expected`, `phase0`, `logs`, `world`). `src/edges/lps_http.pl` is left out
deliberately: it cannot load here, by design.

```sh
./myswipl.sh -q -g "use_module('wasm/pack'), print_payload_files, halt." | less
```

## What is not there

| | Why | What the user sees |
|---|---|---|
| **Streaming and interrupting** the assistant | it runs in the request, not on a thread of its own | its output arrives in one piece when it is done, and *Stop* has nothing left to stop |
| **Live sessions** (`/ide` ▸ Live) | a websocket to a thread that keeps cycling | the live panel does not connect |
| **The MCP endpoint** and the REST surface | those are addresses *other programs* call; this deployment is a page, not a server | an MCP client cannot use this deployment — use the fly.io one |
| **Interrupting** a run from outside it | the interrupt arrives on another thread, and there is one | a run goes to its limit |
| **The token** (`LPS_TOKEN`) | there is nobody else's machine to protect | no token is asked for |
| **Sentry**, web analytics | no server to report to | `/telemetry.js` is an empty file |
| **Logical English**, without `--with-le` | the payload has no LE2 in it | `.le` says which variable to set — as a server without one does |
| **Deploy as Solidity** and the **DRL front end** | they are `vendor/lpsplus`, which the payload does not carry (`src/syntax/lps_plus.pl`) | the same answer a server built without lpsPlus gives |

**The assistant itself does work.** It never needed a sub-process — it is a
Prolog loop over a model and in-process tools — only a thread, and where there
is none it runs in the request instead (`src/edges/lps_assistant.pl`, guarded
by `current_prolog_flag(threads, true)`). What it needs from the deployment is
a way to reach its model, which is what `/api/proxy` is for; the payload
carries `docs/user/**.md` so that it searches and cites the documentation as
the server's does.

And one difference that is not an absence: **a time limit is counted in
inferences, not seconds** (`wasm/shims/time.pl`). There is no clock to
interrupt a goal with, so the budget is `seconds × 6 million` inferences by
default. A program that runs away still stops; a slow, legitimate one may stop
early, and `inferencesPerSecond` in `config.js` is the dial.

The **first request waits for the engine**: measured on a two-core container
over localhost, about **2 seconds** from opening the IDE to an engine that
answers, and about 1.9 s with the runtime and the payload already cached —
LPS2 has rather less to consult than Logical English does. A real laptop is
faster and a real network slower; the shape is the same.

## How it works

```
  the IDE (ui/src/api.js)
      │  fetch('/lpsapi', {…})        ← unchanged: the IDE was never told
      ▼
  lps-wasm/boot.js                    ← replaces window.fetch, in <head>
      │  postMessage
      ▼
  lps-wasm/worker.js                  ← a Web Worker: SWI-Prolog + the payload
      │  lps_wasm_app:lps_wasm_call(JSON, Reply)
      ▼
  wasm/lps_wasm_app.pl  →  src/edges/lps_api.pl  →  src/core/, src/syntax/
```

* **`src/edges/lps_api.pl`** — the operations, with no HTTP in them: extracted
  from `lps_http.pl`, which keeps the server, the routes, the pages, the
  assets, the token and the MCP envelope, and delegates.
* **`wasm/lps_wasm_app.pl`** — the browser transport: JSON string in, JSON
  string out, plus the way back out to the page.
* **`wasm/shims/`** — the libraries the WebAssembly image does not have, each
  standing in for one; `wasm/shims/README.md` is the list. `src/core/` needs
  none of them, and that is not luck: `tools/lint_core.pl` has been enforcing
  it since M1.
* **`wasm/pack.pl`, `wasm/runtime/mkpayload.mjs`** — what ships, as one gzipped
  file rather than four hundred requests.
* **`wasm/runtime/boot.js`, `worker.js`** — the interception and the engine.
  `boot.js` answers `/lpsapi`, `/lpsapi/status` and `/telemetry_test`;
  everything else is a file and goes through the real `fetch`.

## Testing it

`tools/ide_check.cjs` — which drives the IDE in a real browser and fails on
any console error, page error or failed request — runs against the static
build exactly as it runs against the server:

```sh
./wasm/build.sh --skip-ui
node wasm/runtime/serve.mjs wasm/dist 8090 &
NODE_PATH=$(npm root -g) node tools/ide_check.cjs build/ide-shots-wasm 8090
```

On the build of 2026-09-20 it walks every pane — the editor, the timeline, the
changes diagram, the automaton, the 2D scene, the scene strip, the internal
syntax, the explanations, the diagnostics, the integrations map, File ▸ Open
of a PDDL pair and an Inform story — and the start page's 293 example links
all resolve. With `--with-le` it also edits and runs Logical English, follows
*Show definition* into an included resource, compiles a `.le` with its `.lps`
companion as one program, and plays a story. The one step it cannot do is the
assistant's, which needs a model — the loop itself was driven end to end in
the engine with a scripted one, and answered as it does on a server.

Without `--with-le` the same run reports two problems, and they are the same
problem twice: a `.le` document cannot be compiled, because the build carries
no Logical English. That is the message a server without `LPS_LE2_LIB` gives,
word for word.

## Troubleshooting

**"The LPS2 engine could not start"** at the bottom of the page: the worker
says why in the browser console. The usual causes are a `payload.bin` that was
re-encoded in transit and a host that will not serve `.wasm` as
`application/wasm`.

**A program does not parse, with a syntax error at its first `actions` or
`fluents` line.** That is the operator table: something is reading the program
in a module that has not imported `lps_ops`. It is fixed, but it is the
failure to expect if the payload's module layout ever changes.

**An operation answers `{"ok": false, "error": "no such predicate: …"}`.** A
predicate the payload does not carry: add its file to `wasm/pack.pl`.

**`.le` says Logical English is not configured.** The build was made without
`--with-le`, or `vendor/le2` was empty when it was made.

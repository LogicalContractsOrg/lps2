# Deploying LPS(2)

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
docker build -t lps2 .
docker run -p 3060:3060 lps2            # http://localhost:3060/
```

## fly.io

```sh
fly launch --no-deploy                  # once, if the app does not exist
fly secrets set LPS_TOKEN=$(openssl rand -hex 24)
./buildPush.sh                          # build locally, then fly deploy --local-only
```

`buildPush.sh` builds locally rather than on fly's remote builder, for the same
reason LE2's does: the build stamps the image with the git revision it came
from, and a remote builder would stamp whatever it happened to fetch. What is
deployed is then the image that was actually tested.

On a Mac the Docker socket usually needs pointing at first:

```sh
export DOCKER_HOST=unix:///Users/$USER/.docker/run/docker.sock
```

## Configuration

| variable | meaning |
|---|---|
| `LPS_PORT` | the port to serve on. Default 3060. |
| `LPS_TOKEN` | required in every request body as `"token"`. **Set it.** |
| `LPS_LE2_URL` | an LE2 `/leapi` endpoint, so `.le` programs compile |
| `LPS_LE2_DIR` | an LE2 checkout, as an alternative to the URL |

### `LPS_TOKEN` is not optional in a public deployment

`/lpsapi compile` takes a program and runs it, and an LPS program may call
arbitrary Prolog — that is the language, not a hole in it. An untokened
deployment reachable from the internet is therefore an open Prolog
interpreter. `./lps ide` prints `no token: every request is accepted` when
there is none, and `buildPush.sh` warns before deploying without one, so the
state you are in is never a surprise; neither of them refuses, because a
tokenless server on a laptop is exactly what you want while developing.

## Running it alongside LogicalEnglish2

LPS(2) does not parse Logical English. LE2 does, and the two talk over HTTP —
`docs/le_lps_interface.md` is the contract. So a deployment that is meant to
run `.le` programs is **two apps**, not one:

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

and, for the CLI or for a headless client, LPS(2) reaches LE2 itself:

```sh
fly secrets set LPS_LE2_URL=https://logicalenglish2.fly.dev/leapi
```

**Two apps and no proxy**, deliberately (`docs/le_lps_design.md` §3). Proxying
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

### One box, for development

If you would rather run both locally without two containers, LPS(2) can shell
out to an LE2 *checkout* instead of an endpoint:

```sh
export LPS_LE2_DIR=/path/to/LogicalEnglish2
./lps run examples/lps/fire_simple.le
```

That runs LE2 in a child SWI-Prolog, which is also what the conformance work
does — a `.le` document can pull in arbitrary Prolog resources, and one
document's `halt/0` should not take the CLI with it.

## What is in the image, and why

| copied | why |
|---|---|
| `src/` | the engine, the syntax layer, the edges, the IDE page |
| `examples/` | LPS(2)'s own examples, offered by the IDE's example picker |
| `legacy_lps1/` | not optional: the IDE offers its CLOUT_workshop programs, and ten corpus programs `:- include(system('date_utils.pl'))` |
| `conformance/`, `tools/` | so `./lps test` and the lint work in the container |
| `docs/` | so the deployed thing carries its own documentation |

`build/` is excluded — it is scratch: work directories, engine variants, run
logs, generated reports and IDE screenshots.

The build ends with

```dockerfile
RUN swipl -q -g "consult('src/lps.pl')" -g "halt(0)" -t "halt(1)"
```

so a program that does not load fails the *build* rather than the running
server.

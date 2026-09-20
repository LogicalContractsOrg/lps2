# Library shims for the WebAssembly build

SWI-Prolog's WebAssembly image is the full system minus the parts that need an
operating system underneath: no threads, no sockets, no sub-processes, no
timers. The libraries LPS2's *edges* import that are therefore missing from it
are stood in for here — and a missing library is a *load* failure, so without
these the edges do not exist and neither does anything above them.

`src/core/` needs none of this, and that is not luck: `tools/lint_core.pl` has
been enforcing "no threads, no clock, no foreign code, no files" on the engine
since M1, which is the reason the engine was known to run in a browser before
anyone tried (`src/edges/lps_wasm.pl`, M11).

| Shim | Stands in for | What it does instead |
|------|---------------|----------------------|
| `time.pl` | `library(time)` | bounds a goal by *inferences* rather than seconds |
| `process.pl` | `library(process)` | refuses: there are no sub-processes in a browser tab |
| `http/json.pl` | `library(http/json)` | re-exports `library(json)`, which the image has |
| `http/http_json.pl` | `library(http/http_json)` | the reading half; the reply half refuses |
| `http/http_open.pl` | `library(http/http_open)` | fetches through the browser, synchronously |
| `http/http_client.pl` | `library(http/http_client)` | `http_post/4` over the above |
| `http/http_ssl_plugin.pl` | `library(http/http_ssl_plugin)` | nothing: the browser's TLS is already on |

They are on the library search path of the WASM build only
(`wasm/lps_wasm_app.pl` puts them there); nothing in the server build sees
them, and no file outside this directory is written differently because they
exist.

The same set, with two more (`www_browser`, `http/http_session`), is in the
Logical English repository at `wasm/shims/`. They are deliberately separate
copies: this build has to work in a checkout with no LE2 in it.

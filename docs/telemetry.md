# Error reports and analytics: Sentry and PostHog

The LPS2 server can report errors to [Sentry](https://sentry.io) — its own
exceptions and those of the IDE — offer a small **Feedback** form (Sentry's
User Feedback), and send [PostHog](https://posthog.com) page views,
autocaptured clicks and the IDE's main actions.

**Both are off unless the server's environment configures them.** With no
variable set, nothing is loaded and nothing leaves the server or the
browser: every page still asks for `/telemetry.js`, which then answers one
line defining a function that does nothing. That is how the tools, the
browser tests and `./lps ide` on a laptop run.

LogicalEnglish2's server has the same, in its own Sentry and PostHog
projects (its `docs/telemetry.md`, variables `LE_…`). The prefixes keep them
apart: LPS2 loads Logical English into its process, and still reports only
into the LPS2 projects.

## What is sent, and what is not

| | Sent | Not sent |
|---|---|---|
| Server → Sentry | the `/lpsapi` operation's name (`run`, `compile`, …), the error's type and message (at most 1000 characters), the Prolog backtrace when the error carries one, environment, release | the program, the events observed, any other field of the request, the user's name or IP |
| Browser → Sentry | uncaught errors of the page, with the SDK's default context (browser, URL) and `sendDefaultPii: false` | console output (the IDE logs programs), screenshots (the feedback form has none: it would show the program) |
| Feedback form → Sentry | the message typed, and a name and email **only if** the user types them | — |
| Browser → PostHog | page views; clicks, with the element's id and classes but **every text masked** (the editor's text is the user's program); the main actions below | session recordings (off), input values, cookies (see *Persistence*) |

Every page address that is reported — an error's, the feedback form's, a
page view's and every address among PostHog's properties — loses its
fragment and every query parameter but `example`: an editor link can
carry a whole program (`?text=…`, `#lzp=…`). PostHog's feature flags are
turned off, since their requests would send the first address unfiltered.

An error message is written by the code that raised it, and a few Prolog
errors quote the term they were about; with 1000 characters at most, that is
the one way a fragment of a program could reach Sentry.

The server sends a report from a thread of its own, with a five-second
timeout; the same error at most once in ten minutes, and at most sixty
reports an hour. An unreachable Sentry never slows or fails a request.

### The main actions (PostHog events)

Recognised by the operation each call to `/lpsapi` names
(`src/edges/lps_telemetry.pl`, `api_event/3`); only these fields travel with
them:

| Event | Operation | Properties |
|---|---|---|
| `example opened` | `example` | `example` (its name) |
| `program run` / `program stepped` | `run` / `step` | |
| `live session started`, `play started`, `why asked` | `live_start`, `play_start`, `explain` | |
| `deployed as Solidity`, `standalone page made` | `to_solidity`, `wasm_bundle` | |
| `program exported` | `export` | `format` |
| `file imported` | `convert` | `extension` |
| `legal view opened`, `assistant used` | `le_legal_view`, `assistant_command` | |

The IDE can send more with `window.lpsTrack(name, props)` (a no-op when
PostHog is off).

## The variables

| Variable | Meaning | Default |
|---|---|---|
| `LPS_SENTRY_DSN` | the Sentry project's DSN: turns Sentry on | off |
| `LPS_SENTRY_ENVIRONMENT` | Sentry's *environment* | `production` |
| `LPS_SENTRY_RELEASE` | Sentry's *release* | `lps2@<build stamp>` from `src/ide/dist/BUILD.txt` |
| `LPS_POSTHOG_KEY` | the PostHog project's API key (`phc_…`): turns PostHog on | off |
| `LPS_POSTHOG_HOST` | PostHog's ingestion host | `https://eu.i.posthog.com` (EU cloud) |
| `LPS_POSTHOG_PERSISTENCE` | where PostHog keeps its anonymous id | `memory` |

## 1. The Sentry project

1. Sign in at <https://sentry.io>.
2. **Projects ▸ Create Project**. Platform: **Browser JavaScript**. Alert
   frequency: *Alert me on every new issue*. Name: `lps2`. Create it (skip
   the SDK instructions: the pages load the SDK themselves).
3. Copy the **DSN**: *Settings ▸ Projects ▸ lps2 ▸ Client Keys (DSN)*. The one
   DSN serves both reporters: the browser SDK and the server's Prolog
   reporter (`lps_telemetry.pl`, which speaks Sentry's envelope protocol).
   Server events carry the tag `server: lps2` and platform `other`.
4. **Allowed domains**: *Settings ▸ Projects ▸ lps2 ▸ General Settings ▸
   Client Security ▸ Allowed Domains*: `lps2.fly.dev` (and any other host
   the IDE is reached at).
5. **Privacy**: *Settings ▸ Projects ▸ lps2 ▸ Security & Privacy*: keep *Data
   Scrubber* on, and turn on *Prevent Storing of IP Addresses*.
6. **User Feedback** needs nothing enabling: what users send appears under
   *User Feedback* in the sidebar (or *Issues ▸ Feedback*).
7. **Alerts**: the project comes with *new issue → email*; add, if wanted,
   *Alerts ▸ Create Alert ▸ Issues ▸ Number of events in an issue is more
   than 20 in one hour → notify the team*.

## 2. The PostHog project

1. Sign in at <https://eu.posthog.com> (or <https://us.posthog.com>, and then
   `LPS_POSTHOG_HOST=https://us.i.posthog.com`).
2. *Project switcher ▸ New project*: `LPS2`.
3. Copy the **Project API key** (`phc_…`): *Settings ▸ Project ▸ General*.
4. *Settings ▸ Project ▸ Autocapture & heatmaps*: **Autocapture** on.
5. *Settings ▸ Session replay*: **Record user sessions** off (the pages
   disable it too).
6. *Settings ▸ Project ▸ Toolbar / Authorized URLs*: `https://lps2.fly.dev`.
7. *Settings ▸ Project ▸ General ▸ IP data capture*: **Discard client IP
   data** on.

## 3. Setting the variables on fly.io

The app is `lps2` (`fly.toml`). The values are not secret (both end up in
every page), but fly secrets keep `fly.toml` unchanged:

```sh
fly secrets set -a lps2 \
    LPS_SENTRY_DSN='https://<key>@o<nnn>.ingest.de.sentry.io/<nnn>' \
    LPS_POSTHOG_KEY='phc_<key>'
# only for a US PostHog project:
fly secrets set -a lps2 LPS_POSTHOG_HOST='https://us.i.posthog.com'
```

`fly secrets set` restarts the machine (`--stage` waits for the next
deploy). `fly secrets unset -a lps2 LPS_POSTHOG_KEY` turns one off. Locally,
export them before `./lps ide`, with `LPS_SENTRY_ENVIRONMENT=development`.

## 4. Checking it works

- **Server**: `https://lps2.fly.dev/telemetry_test` answers
  `{"sentry": true, "posthog": true, "sentry_test": "sent", …}` and sends a
  test error, `telemetry_test` (`server: lps2`), to Sentry. It is throttled
  like any report — once in ten minutes.
- **Browser errors**: in the IDE's console,
  `Sentry.captureException(new Error('browser check'))`.
- **Feedback**: the *Feedback* button, bottom right.
- **PostHog**: *Activity* shows `$pageview`, `$autocapture`, and
  `example opened` / `program run` after opening and running an example.
  (PostHog drops events from browsers it takes for bots — a headless test
  browser included.)

`tools/telemetry_test.pl` checks the DSN parsing, the envelope, the
throttling and that nothing happens unconfigured, against a mock Sentry on
a local port.

## Persistence, cookies and consent

By default PostHog keeps its anonymous id in memory only — **no cookie, no
local storage** — so each page load is a new anonymous visitor: actions and
page views are counted, "unique users" and retention are not meaningful.
Chosen so that no consent banner is needed for PostHog under the EU's
ePrivacy rules and GDPR. `LPS_POSTHOG_PERSISTENCE=localStorage+cookie`
recognises returning visitors, and may then require consent (a cookie
banner) where EU law applies. Sentry stores nothing on the device.

## Where the code is

- `src/edges/lps_telemetry.pl` — configuration, the server's reports,
  `/telemetry.js`, `/telemetry_test`, and the script tag put into every HTML
  page the server sends (`telemetry_page/2`, used by `serve_file/1`, the
  landing page and the docs shell) — so the built IDE needs no rebuild.
- `src/edges/lps_telemetry.js` — the pages' client: Sentry's pinned CDN
  bundle (with its integrity hash) and the PostHog snippet. A copy of LE2's
  `web_extras/telemetry/telemetry.js`: change both.
- `src/edges/lps_http.pl` — the handlers, and the report in `lpsapi/1`.

If a Content Security Policy is ever added, it must allow
`browser.sentry-cdn.com` (scripts), `*.ingest.sentry.io` (connect) and the
PostHog host and its assets host (`eu.i.posthog.com`,
`eu-assets.i.posthog.com`).

# Error reports and web analytics: Sentry and Cloudflare

*Kind: operations · Audience: developers, operators · Status: current (2026-09-16)*

The LPS2 server can report errors to [Sentry](https://sentry.io) — its own
exceptions and those of the IDE — offer a small **Feedback** form (Sentry's
User Feedback), and load [Cloudflare Web
Analytics](https://developers.cloudflare.com/web-analytics/) on its pages.

**Both are off unless the server's environment configures them, and only the
deployed server's does** (fly secrets, §3). With no variable set, nothing is
loaded and nothing leaves the server or the browser: every page still asks
for `/telemetry.js`, which then answers a comment. That is how the tools,
the browser tests and `./lps ide` on a laptop run.

LogicalEnglish2's server has the same, with its own Sentry project and Web
Analytics site (its `docs/dev/telemetry.md`, variables `LE_…`). The prefixes keep
them apart: LPS2 loads Logical English into its process, and still reports
only into its own.

## What is sent, and what is not

| | Sent | Not sent |
|---|---|---|
| Server → Sentry | the `/lpsapi` operation's name (`run`, `compile`, …), the error's type and message (at most 1000 characters), the Prolog backtrace when the error carries one, environment, release | the program, the events observed, any other field of the request, the user's name or IP |
| Browser → Sentry | uncaught errors of the page, with the SDK's default context (browser, URL) and `sendDefaultPii: false` | console output (the IDE logs programs), screenshots (the feedback form has none: it would show the program) |
| Feedback form → Sentry | the message typed, and a name and email **only if** the user types them | — |
| Browser → Cloudflare Web Analytics | Cloudflare's beacon: page views (the page's path, referrer, country, browser and device class) and page-load performance | cookies, local storage, fingerprinting, the page's contents, clicks, programs |

Every page address Sentry reports — an error's, the feedback form's — loses
its fragment and every query parameter but `example`: an editor link can
carry a whole program (`?text=…`, `#lzp=…`). The Cloudflare beacon is
Cloudflare's own script and reads the page's address itself; its dashboard
reports paths. Check *Top paths* after the first deployment (§4).

One class of browser report is dropped before it is sent (`ignoreErrors` in
`lps_telemetry.js`): "Object Not Found Matching Id:*N*, MethodName:update,
ParamCount:4". It is not this page's error. Outlook — and the Office link
scanner behind it — opens an address in a browser of its own and injects a
script into the page; when that script fails, the page is what reports it,
with no stack, from a window nobody was looking at. Nothing here can cause
it or fix it.

A second class is dropped too: "Canceled: Canceled" from the code editor
(Monaco) in Safari. On every click and key press the editor gets a copy to
the clipboard ready, in case one follows, and cancels the one it got ready
before. Safari reports each cancelled copy as an error nobody handled.
Nothing is wrong, and copying still works.

An error message is written by the code that raised it, and a few Prolog
errors quote the term they were about; with 1000 characters at most, that is
the one way a fragment of a program could reach Sentry.

The server sends a report from a thread of its own, with a five-second
timeout; the same error at most once in ten minutes, and at most sixty
reports an hour. An unreachable Sentry never slows or fails a request.

## The variables

| Variable | Meaning | Default |
|---|---|---|
| `LPS_SENTRY_DSN` | the Sentry project's DSN: turns Sentry on | off |
| `LPS_SENTRY_ENVIRONMENT` | Sentry's *environment* | `production` |
| `LPS_SENTRY_RELEASE` | Sentry's *release* | `lps2@<build stamp>` from `src/ide/dist/BUILD.txt` |
| `LPS_CLOUDFLARE_ANALYTICS_TOKEN` | the Web Analytics site's token: turns the beacon on | off |

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
   Client Security ▸ Allowed Domains*: `lps2.logicalcontracts.com` and
   `lps2.fly.dev` (every host the IDE is reached at).
5. **Privacy**: *Settings ▸ Projects ▸ lps2 ▸ Security & Privacy*: keep *Data
   Scrubber* on, and turn on *Prevent Storing of IP Addresses*.
6. **User Feedback** needs nothing enabling: what users send appears under
   *User Feedback* in the sidebar (or *Issues ▸ Feedback*).
7. **Alerts**: the project comes with *new issue → email*; add, if wanted,
   *Alerts ▸ Create Alert ▸ Issues ▸ Number of events in an issue is more
   than 20 in one hour → notify the team*.

## 2. The Cloudflare Web Analytics site

The site already exists; its token is `156f86d887d3403980efe3773373da6f`.
To create it again, or check its settings:

1. Sign in at <https://dash.cloudflare.com> ▸ **Analytics & Logs ▸ Web
   Analytics** ▸ **Add a site**.
2. Hostname: `lps2.logicalcontracts.com`, the public address (not proxied by Cloudflare, so the JS snippet is
   the way in; no DNS change).
3. Cloudflare shows the snippet:

   ```html
   <!-- Cloudflare Web Analytics --><script type='module' src='https://static.cloudflareinsights.com/beacon.min.js' data-cf-beacon='{"token": "156f86d887d3403980efe3773373da6f"}'></script><!-- End Cloudflare Web Analytics -->
   ```

   Do **not** paste it into the pages: only its token is needed. The server
   adds the same script to every page it serves (`lps_telemetry.js`), and
   only when the token is set, so local runs and tests are never counted.
4. The token is not secret (it ends up in every page); it is a fly secret so
   that only the deployed server has it.

## 3. Setting the variables on fly.io

The app is `lps2` (`fly.toml`). The values are not secret (both end up in
every page), but as fly secrets they stay out of `fly.toml`, the image and
every other environment: only the deployed server reports.

```sh
fly secrets set -a lps2 \
    LPS_SENTRY_DSN='https://<key>@o<nnn>.ingest.de.sentry.io/<nnn>' \
    LPS_CLOUDFLARE_ANALYTICS_TOKEN='156f86d887d3403980efe3773373da6f'
fly secrets list -a lps2        # names and digests, to check
```

`fly secrets set` restarts the machine (`--stage` waits for the next
deploy). `fly secrets unset -a lps2 LPS_CLOUDFLARE_ANALYTICS_TOKEN` turns
it off. Do not set the token locally (local visits would be counted); to try
Sentry locally, export `LPS_SENTRY_DSN` before `./lps ide`, with
`LPS_SENTRY_ENVIRONMENT=development`.

## 4. Checking it works

- **Server**: `https://lps2.fly.dev/telemetry_test` answers
  `{"sentry": true, "web_analytics": true, "sentry_test": "sent", …}` and sends a
  test error, `telemetry_test` (`server: lps2`), to Sentry. It is throttled
  like any report — once in ten minutes.
- **Browser errors**: in the IDE's console,
  `Sentry.captureException(new Error('browser check'))`.
- **Feedback**: the *Feedback* button, bottom right.
- **Web Analytics**: in the browser's developer tools (*Network*), a page
  loads `static.cloudflareinsights.com/beacon.min.js` and posts to
  `cloudflareinsights.com/cdn-cgi/rum`; the dashboard (*Web Analytics ▸
  lps2.fly.dev*) shows the visits within minutes. In *Top paths*, check that
  `?text=…` links do not appear with their query string.

`tools/telemetry_test.pl` checks the DSN parsing, the envelope, the
throttling and that nothing happens unconfigured, against a mock Sentry on
a local port.

## Cookies and consent

Cloudflare Web Analytics sets no cookie and uses no local storage, and Sentry
stores nothing on the device, so neither needs a consent banner under the
EU's ePrivacy rules. Turn on *Prevent Storing of IP Addresses* in Sentry
(step 1.5).

## Where the code is

- `src/edges/lps_telemetry.pl` — configuration, the server's reports,
  `/telemetry.js`, `/telemetry_test`, and the script tag put into every HTML
  page the server sends (`telemetry_page/2`, used by `serve_file/1`, the
  landing page and the docs shell) — so the built IDE needs no rebuild.
- `src/edges/lps_telemetry.js` — the pages' client: Sentry's pinned CDN
  bundle (with its integrity hash) and Cloudflare's beacon. A copy of LE2's
  `web_extras/telemetry/telemetry.js`: change both.
- `src/edges/lps_http.pl` — the handlers, and the report in `lpsapi/1`.

If a Content Security Policy is ever added, it must allow
`browser.sentry-cdn.com` and `static.cloudflareinsights.com` (scripts), and
`*.ingest.sentry.io` and `cloudflareinsights.com` (connect).

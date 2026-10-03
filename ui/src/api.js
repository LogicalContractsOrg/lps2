/* api.js — the one channel.
 *
 * Everything the IDE does is a POST to /lpsapi with an `operation` field, so
 * anything on screen can be reproduced with curl. That is not a slogan: it is
 * what keeps the endpoint independently testable, and it is the rule the M14
 * editor inherited from the reference client it replaces.
 */

const BASE = window.LPS_API_BASE || '/lpsapi';

/*  The token, and how it gets here.
 *
 *  A deployment with `LPS_TOKEN` set refuses every operation without one, so a
 *  link to such a server has to be able to carry it: `?token=…` is read once,
 *  stored, and *removed from the address bar*, so it does not sit in the
 *  history or get copied into a chat window with the next share link. LE2's
 *  editor takes its own the same way. */
let token = localStorage.getItem('lps-token') || '';
(function tokenFromUrl() {
  try {
    const u = new URL(location.href);
    const t = u.searchParams.get('token');
    if (!t) return;
    token = t;
    localStorage.setItem('lps-token', token);
    u.searchParams.delete('token');
    history.replaceState(null, '', u.toString());
  } catch { /* no URL API, no harm */ }
}());

/*  The page and the API have to be on the same origin, and only the server
 *  can say which one that is.
 *
 *  A page opened at `http://…` on a deployment that redirects to https (which
 *  is every deployment of this: fly.toml sets force_https) looks like it
 *  works — a GET follows the redirect and comes back 200 — but a POST does
 *  not: a 301 turns it into a GET, /lpsapi answers GET with 405, and every
 *  operation the IDE has fails with "HTTP 405" while the editor itself looks
 *  fine. The editor's worker goes the same way (main.js). Neither is
 *  fixable from the server, which never sees those requests.
 *
 *  So take the answer from the response: fetch reports the origin it ended up
 *  on, and if that is not the page's, the page is on the wrong one and moves
 *  there. Three limits on that, because navigating is not a small thing to do
 *  to somebody: only for a server this page is asking at a relative address
 *  (a deployment that sets LPS_API_BASE to another origin means it), only to
 *  the same host — the same server over https, or on another port, never
 *  somewhere else a redirect points — and only once per tab, so that a
 *  redirect that leads back cannot bounce the page for ever. */
const MOVED = 'lps-origin-moved';
function sameOriginOrMove(r) {
  if (!r || !r.redirected || /^https?:/i.test(BASE)) return;
  let u;
  try { u = new URL(r.url); } catch { return; }
  if (u.origin === location.origin || u.hostname !== location.hostname) return;
  try {
    if (sessionStorage.getItem(MOVED)) return;
    sessionStorage.setItem(MOVED, u.origin);
  } catch { /* private mode: one move without the guard is better than none */ }
  location.replace(u.origin + location.pathname + location.search + location.hash);
}

export const setToken = (t) => { token = t || ''; localStorage.setItem('lps-token', token); };
export const getToken = () => token;

/*  What went wrong, in the words the server actually used.
 *
 *  A refusal carries `error` *or* a diagnostics array, and `compile` is the
 *  common case of the second: it answers `ok: false` with a syntax error at a
 *  line and column, and no `error` field at all. Reading only `error` turned
 *  every failed compile into the words "unknown error" — which is how pressing
 *  Run on a program with a missing full stop came to say nothing useful. */
function errorText(j) {
  if (j.error) return String(j.error);
  //  A Logical English compile puts the English half's problems in `issues`
  //  and the LPS half's in `diagnostics`; either can hold the one that failed.
  //  Reading only the second said "unknown error" about a document whose every
  //  error was a sentence LPS has no reading for.
  const first = [...(j.diagnostics || []), ...(j.issues || [])].find((d) => d.severity === 'error');
  if (!first) return 'unknown error';
  const at = first.source?.line ? ` (line ${first.source.line})` : '';
  return `${first.message}${at}`;
}

export class ApiError extends Error {
  constructor(message, op, reply = null) {
    super(message);
    this.operation = op;
    //  The refusal itself, when the server sent one: a caller that can place
    //  its diagnostics at their lines should not have to make do with the
    //  first one's text.
    this.reply = reply;
    //  The one failure a caller has to treat differently: it is not about the
    //  request, and retrying it unchanged will fail the same way for ever.
    this.unauthorised = /unauthoris|unauthoriz/i.test(String(message));
    //  The other one: the id is of a process that is gone (the deployment stops
    //  its machine when idle), so the call is fine and only the handle is dead.
    //  Making a new one is the IDE's job, not the reader's — main.js re-runs.
    this.stale = !!(reply && reply.stale);
  }
}

/*  Does this server want a token, and does it have Logical English? Asked
 *  before anything else, because "unauthorised" on the first call is otherwise
 *  the only way to find out — and that call is usually one whose failure the
 *  UI swallows. Unauthenticated by design: that a server requires a token is
 *  the first thing a refused client learns anyway. */
let statusReply = null;
export function serverStatus() {
  //  Asked once: boot asks for it first of all, for the origin check above,
  //  and again later for the token, and one GET answers both.
  if (!statusReply) {
    statusReply = (async () => {
      try {
        const r = await fetch(BASE + '/status', { method: 'GET' });
        sameOriginOrMove(r);
        return r.ok ? await r.json() : { ok: false };
      } catch { return { ok: false }; }
    })();
  }
  return statusReply;
}

export async function api(body) {
  const payload = token ? { ...body, token } : body;
  let r;
  try {
    r = await fetch(BASE, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(payload),
    });
  } catch (e) {
    throw new ApiError(`cannot reach the LPS server (${e.message})`, body.operation);
  }
  //  A POST that was redirected across origins is the one HTTP failure that
  //  is about the address the page was opened at, not about the request.
  if (!r.ok) { sameOriginOrMove(r); throw new ApiError(`${body.operation}: HTTP ${r.status}`, body.operation); }
  const j = await r.json();
  if (j.ok === false) throw new ApiError(errorText(j), body.operation, j);
  return j;
}

/* Analysis is a server round trip, debounced — the pattern LE2 established and
 * the one WASM would remove (§I.10.1). The failure mode this wrapper exists to
 * prevent is the one the reference client shipped with: a thrown analysis
 * returns no `diagnostics` field, and a missing field must never render as
 * "no errors". */
/* An LPS program of the older syntax, as a Logical English document. The
   reply carries the document, the name it should be saved under, and
   everything the converter could not carry over. */
export async function toLe(source, name) {
  return api({ operation: 'to_le', source, name });
}

export async function analyse(source, syntax) {
  return (await analyseFull(source, syntax)).diagnostics;
}

/*  The same call, with the program *profile* the reply also carries: which
 *  events and actions it declares, whether it has display clauses, its
 *  maxTime, whether it plans. Four things the editor used to guess at. */
export async function analyseFull(source, syntax) {
  const r = await api({ operation: 'analyse', source, syntax });
  if (!Array.isArray(r.diagnostics)) {
    throw new ApiError('the server returned no diagnostics field', 'analyse');
  }
  return r;
}

export const compile = (source, syntax) =>
  api({ operation: 'compile', source, syntax });

export const sessionNew = (program, options) =>
  api({ operation: 'session_new', program, ...(options || {}) });

export const run = (session, cycles) =>
  api({ operation: 'run', session, ...(cycles ? { cycles } : {}) });

export const trace = (session) => api({ operation: 'trace', session });
export const timeline = (session) => api({ operation: 'timeline', session });
export const changes = (session, cycle) => api({ operation: 'changes', session, cycle });
export const scene = (session, cycle) => api({ operation: 'scene', session, cycle });
export const scene3d = (session, cycle) => api({ operation: 'scene3d', session, cycle });
export const automaton = (session, opts) => api({ operation: 'automaton', session, ...(opts || {}) });
//  What is worth drawing of this run: the fluents that tell its states apart,
//  the cycles worth a frame, the states it comes back to (AnimationPlan §5).
export const focus = (session) => api({ operation: 'focus', session });
//  One scene per keyframe, with what moved the story on between them (§7).
export const scenes = (session, kind) => api({ operation: 'scenes', session, kind });
export const explain = (session, question) => api({ operation: 'explain', session, question });
export const state = (session) => api({ operation: 'state', session });
export const dump = (program) => api({ operation: 'dump', program });
export const listExamples = () => api({ operation: 'list_examples' });
export const searchExamples = (query, scope) => api({ operation: 'search_examples', query, scope });
export const example = (name) => api({ operation: 'example', name });
export const resource = (name, source, res) => api({ operation: 'resource', name, source, resource: res });
export const observe = (session, events) => api({ operation: 'observe', session, events });

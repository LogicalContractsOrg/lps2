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

export const setToken = (t) => { token = t || ''; localStorage.setItem('lps-token', token); };
export const getToken = () => token;

export class ApiError extends Error {
  constructor(message, op) {
    super(message);
    this.operation = op;
    //  The one failure a caller has to treat differently: it is not about the
    //  request, and retrying it unchanged will fail the same way for ever.
    this.unauthorised = /unauthoris|unauthoriz/i.test(String(message));
  }
}

/*  Does this server want a token, and does it have Logical English? Asked
 *  before anything else, because "unauthorised" on the first call is otherwise
 *  the only way to find out — and that call is usually one whose failure the
 *  UI swallows. Unauthenticated by design: that a server requires a token is
 *  the first thing a refused client learns anyway. */
export async function serverStatus() {
  try {
    const r = await fetch(BASE + '/status', { method: 'GET' });
    if (!r.ok) return { ok: false };
    return await r.json();
  } catch { return { ok: false }; }
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
  if (!r.ok) throw new ApiError(`${body.operation}: HTTP ${r.status}`, body.operation);
  const j = await r.json();
  if (j.ok === false) throw new ApiError(j.error || 'unknown error', body.operation);
  return j;
}

/* Analysis is a server round trip, debounced — the pattern LE2 established and
 * the one WASM would remove (§I.10.1). The failure mode this wrapper exists to
 * prevent is the one the reference client shipped with: a thrown analysis
 * returns no `diagnostics` field, and a missing field must never render as
 * "no errors". */
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
export const explain = (session, question) => api({ operation: 'explain', session, question });
export const state = (session) => api({ operation: 'state', session });
export const dump = (program) => api({ operation: 'dump', program });
export const listExamples = () => api({ operation: 'list_examples' });
export const example = (name) => api({ operation: 'example', name });
export const observe = (session, events) => api({ operation: 'observe', session, events });

/* live-view.js — a 2D or 3D animation attached to a *running* session (M18).
 *
 * The IDE's own scene panes scrub a finished trace; this one follows a session
 * that is still going, in its own window, so it can be put on a second screen
 * while the program runs. It polls `live_scene`, which returns whatever cycle
 * the session has reached — there is no slider, because there is no end.
 *
 * Mouse events (§I.10.4d) go the other way: a program that defines
 * `lps_mousedown/3`, `lps_mouseup/3` or `lps_mousedrag/3` gets them injected as
 * observations, so an animation can be an interface rather than a picture.
 */
import { renderScene2d } from './panes/scene2d.js';
import { renderScene3d } from './panes/scene3d.js';
import { api } from './api.js';

const params = new URLSearchParams(location.search);
const live = params.get('live');
const kind = params.get('kind') === '3d' ? '3d' : '2d';
const view = document.getElementById('view');
const cyc = document.getElementById('cyc');
document.getElementById('title').textContent = `${live} — ${kind.toUpperCase()}`;

const render = kind === '3d' ? renderScene3d : renderScene2d;
let stopped = false;
let paused = false;
let mouseKinds = [];

const $ = (id) => document.getElementById(id);

/*  Pause used to be a request with no visible consequence: the button did not
 *  change, the header did not change, and the cycle counter took one more step
 *  before the driver noticed — which reads exactly like "it did nothing". The
 *  session's own paused flag now drives the header and the buttons. */
function setPaused(p) {
  paused = p;
  $('pause').disabled = p;
  $('resume').disabled = !p;
  document.body.dataset.paused = p ? 'yes' : 'no';
}
setPaused(false);

async function tick() {
  if (stopped) return;
  try {
    const s = await api({ operation: 'live_scene', live, kind });
    if (typeof s.paused === 'boolean' && s.paused !== paused) setPaused(s.paused);
    mouseKinds = s.mouse || [];
    cyc.textContent = `cycle ${s.cycle}` + (paused ? ' · paused' : '');
    if (s.status && s.status !== 'running') {
      cyc.textContent = `cycle ${s.cycle} · ${s.status}`;
      stopped = true;
    }
    render(view, s, s.cycle);
    wireMouse();
  } catch (e) {
    cyc.textContent = e.message;
    stopped = true;
  }
}
setInterval(tick, 700);
tick();

/*  Interactivity, and only when it was asked for.
 *
 *  `lps_mousedown/3`, `lps_mouseup/3` and `lps_mousedrag/3` are injected as
 *  observations carrying scene coordinates. A program that does not declare
 *  them gets nothing — no listener is attached at all, so a click on a picture
 *  stays a click on a picture. The server decides, from the program; the page
 *  only asks. */
let wired = false;
function wireMouse() {
  if (wired || !mouseKinds.length) return;
  wired = true;
  view.style.cursor = 'crosshair';
  let dragging = null;

  /*  Scene coordinates, not pixels. The program laid its scene out in its own
   *  units and its hit test is written in them — `lamp_at(X, N)` in
   *  examples/lights.lps inverts the same arithmetic the display clause used.
   *  Reporting pixels would make every such program depend on the window size.
   *
   *  2D publishes its transform from fit(); 3D publishes a picker, because
   *  a point on the screen is a *ray* in three dimensions and only the scene
   *  can say where it meets the ground. */
  const at = (e) => {
    if (kind === '3d' && window.LPS_SCENE_PICK3D) {
      const p3 = window.LPS_SCENE_PICK3D(e.clientX, e.clientY);
      if (p3) return [Math.round(p3[0]), Math.round(p3[2])];
    }
    const box = view.getBoundingClientRect();
    const px = e.clientX - box.left, py = e.clientY - box.top;
    const t = window.LPS_SCENE_TRANSFORM;
    if (!t || !t.k) return [Math.round(px), Math.round(py)];
    return [Math.round((px - t.px) / t.k), Math.round((t.py - py) / t.k)];
  };

  const send = (name, [x, y]) => {
    if (!mouseKinds.includes(name)) return;
    api({ operation: 'live_observe', live, channel: 'mouse',
          events: [`${name}(${x}, ${y}, left)`] }).catch(() => {});
  };

  view.addEventListener('pointerdown', (e) => {
    if (e.target.closest('.vp-controls')) return;
    dragging = at(e); send('lps_mousedown', dragging);
  });
  view.addEventListener('pointermove', (e) => {
    if (!dragging) return;
    const p = at(e);
    if (p[0] === dragging[0] && p[1] === dragging[1]) return;
    dragging = p; send('lps_mousedrag', p);
  });
  const up = (e) => { if (!dragging) return; send('lps_mouseup', at(e)); dragging = null; };
  view.addEventListener('pointerup', up);
  view.addEventListener('pointercancel', up);
}

$('pause').onclick = async () => { await api({ operation: 'live_pause', live }); setPaused(true); };
$('resume').onclick = async () => { await api({ operation: 'live_resume', live }); setPaused(false); };
$('kill').onclick = async () => {
  await api({ operation: 'live_stop', live });
  stopped = true;
  cyc.textContent = 'stopped';
};

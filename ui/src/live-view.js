/* live-view.js — a 2D or 3D animation attached to a *running* session (M18).
 *
 * The IDE's own scene panes scrub a finished trace; this one follows a session
 * that is still going, in its own window, so it can be put on a second screen
 * while the program runs. It polls `live_scene`, which returns whatever cycle
 * the session has reached — there is no slider, because there is no end.
 */
import { renderScene2d } from './panes/scene2d.js';
import { renderScene3d } from './panes/scene3d.js';
import { api } from './api.js';

const params = new URLSearchParams(location.search);
const live = params.get('live');
const kind = params.get('kind') === '3d' ? '3d' : '2d';
const view = document.getElementById('view');
document.getElementById('title').textContent = `${live} — ${kind.toUpperCase()}`;

const render = kind === '3d' ? renderScene3d : renderScene2d;
let stopped = false;

async function tick() {
  if (stopped) return;
  try {
    const s = await api({ operation: 'live_scene', live, kind });
    document.getElementById('cyc').textContent = `cycle ${s.cycle}`;
    render(view, s, s.cycle);
  } catch (e) {
    document.getElementById('cyc').textContent = e.message;
    stopped = true;
  }
}
setInterval(tick, 700);
tick();

document.getElementById('pause').onclick = () => api({ operation: 'live_pause', live });
document.getElementById('resume').onclick = () => api({ operation: 'live_resume', live });
document.getElementById('kill').onclick = async () => {
  await api({ operation: 'live_stop', live });
  stopped = true;
  document.getElementById('cyc').textContent = 'stopped';
};

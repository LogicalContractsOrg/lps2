/* shared.js — the two things both scene panes need, in neither of them.
 *
 * They were briefly imported across (2D asking 3D for the tooltip, 3D asking 2D
 * for the empty state), which works in ESM and is a circle waiting to bite.
 */

/*  A tooltip that appears when the pointer is on the object, not a second later.
 *
 *  The scene panes used to set `pane.title`, which is the browser's native
 *  tooltip: about a second of delay, no styling, and it vanishes on the
 *  smallest movement — so hovering an object in a scene you are panning around
 *  mostly showed nothing at all. This is a div that follows the pointer. */
let tipEl = null;
export function showTip(pane, text, e) {
  if (!text || !e || e.clientX == null) {
    if (tipEl) { tipEl.remove(); tipEl = null; }
    return;
  }
  if (!tipEl) {
    tipEl = document.createElement('div');
    tipEl.className = 'scene-tip';
    document.body.appendChild(tipEl);
  }
  tipEl.textContent = text;
  const w = tipEl.offsetWidth, h = tipEl.offsetHeight;
  tipEl.style.left = Math.min(window.innerWidth - w - 4, e.clientX + 14) + 'px';
  tipEl.style.top = Math.max(4, e.clientY - h - 8) + 'px';
}

/*  An empty scene pane that offers the one thing worth doing about it. The
 *  button is the assistant's own — clicking here clicks that, so there is one
 *  code path and no second prompt to keep in step. */
export function emptyWithOffer(pane, decl, label, buttonId) {
  const p = document.createElement('p');
  p.className = 'empty';
  p.textContent = `This program declares no ${decl} clauses, so it has no visual mapping.`;
  const b = document.createElement('button');
  b.textContent = label;
  b.title = 'Ask the assistant to write them';
  b.addEventListener('click', () => document.getElementById(buttonId)?.click());
  const doc = document.createElement('a');
  doc.href = '/docs/UsingTheIDE';
  doc.target = '_blank';
  doc.className = 'muted';
  doc.textContent = 'or write them by hand';
  const wrap = document.createElement('div');
  wrap.className = 'empty-actions';
  wrap.append(b, doc);
  pane.replaceChildren(p, wrap);
}

/*  A legend for a scene: which colour and icon stands for which fluent. The
 *  scenes are pictures of a *state*, and a picture whose vocabulary is
 *  undocumented is a puzzle. */
export function sceneLegend(pane, entries) {
  const old = pane.querySelector('.scene-legend');
  if (old) old.remove();
  if (!entries.length) return;
  const box = document.createElement('div');
  box.className = 'scene-legend';
  for (const { colour, label } of entries) {
    const row = document.createElement('div');
    row.className = 'row';
    const sw = document.createElement('span');
    sw.className = 'sw';
    sw.style.background = colour || 'transparent';
    const t = document.createElement('span');
    t.textContent = label;
    row.append(sw, t);
    box.appendChild(row);
  }
  pane.appendChild(box);
}

/*  A small toolbar for a scene pane: the things you want to do *with* the
 *  picture rather than to the camera. Kept out of the viewport's control
 *  cluster, which is about navigation.
 *
 *  "Record" is a WebM, not a GIF: `canvas.captureStream()` and `MediaRecorder`
 *  are in the browser already, and a GIF encoder would be a dependency and a
 *  worse file. It plays the run from the start while it records.
 */
export function sceneToolbar(pane, { canvas, cycle, onCompare }) {
  const old = pane.querySelector('.scene-tools');
  if (old) old.remove();
  const box = document.createElement('div');
  box.className = 'scene-tools';
  const mk = (label, title, fn) => {
    const b = document.createElement('button');
    b.textContent = label; b.title = title;
    b.addEventListener('click', (e) => { e.stopPropagation(); fn(b); });
    box.appendChild(b);
    return b;
  };

  mk('PNG', 'Save this frame as an image', () => {
    const c = typeof canvas === 'function' ? canvas() : canvas;
    if (!c) return;
    const a = document.createElement('a');
    a.href = c.toDataURL('image/png');
    a.download = `scene-cycle-${cycle}.png`;
    a.click();
  });

  mk('Rec', 'Play the run from the start and record it as a video', (b) => {
    const c = typeof canvas === 'function' ? canvas() : canvas;
    if (!c || !c.captureStream || typeof MediaRecorder === 'undefined') {
      b.title = 'this browser cannot record a canvas';
      return;
    }
    if (b.dataset.on) { window.dispatchEvent(new Event('lps-record-stop')); return; }
    const chunks = [];
    const rec = new MediaRecorder(c.captureStream(25), { mimeType: 'video/webm' });
    rec.ondataavailable = (e) => chunks.push(e.data);
    rec.onstop = () => {
      const a = document.createElement('a');
      a.href = URL.createObjectURL(new Blob(chunks, { type: 'video/webm' }));
      a.download = 'run.webm';
      a.click();
      b.textContent = 'Rec'; delete b.dataset.on;
    };
    const stop = () => { if (rec.state !== 'inactive') rec.stop(); window.removeEventListener('lps-record-stop', stop); };
    window.addEventListener('lps-record-stop', stop);
    rec.start();
    b.textContent = '■'; b.dataset.on = '1';
    //  main.js plays the cycles and fires lps-record-stop at the end.
    window.dispatchEvent(new Event('lps-record-play'));
  });

  if (onCompare) mk('⇔', 'Show this cycle beside the one before it', () => onCompare());
  pane.appendChild(box);
}

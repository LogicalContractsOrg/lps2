/* mouse.js — clicks in a scene, injected as observations (§I.10.4d).
 *
 * A program that defines `lps_mousedown/3`, `lps_mouseup/3` or
 * `lps_mousedrag/3` gets them; one that does not has no listener attached at
 * all, so a click on a picture stays a click on a picture.
 *
 * This was in live-view.js, and therefore only worked in the pop-out window.
 * The main window's 2D pane now follows a live session too, and a picture you
 * cannot click is a picture that looks broken — the whole point of
 * examples/start/lights.lps is that the lamps are the interface.
 */
export function wireMouse(view, { api, live, kind, mouseKinds, onNote }) {
  if (!mouseKinds || !mouseKinds.length) return () => {};
  //  The hand, not a crosshair: a crosshair says "place something precisely"
  //  and this is a click target.
  view.style.cursor = 'pointer';
  let dragging = null;

  /*  Scene coordinates, not pixels. The program laid its scene out in its own
   *  units and its hit test is written in them — `lamp_at(X, N)` in
   *  examples/start/lights.lps inverts the same arithmetic the display clause used.
   *  Reporting pixels would make every such program depend on the window size.
   *
   *  2D publishes its transform from fit(); 3D publishes a picker, because a
   *  point on the screen is a *ray* in three dimensions and only the scene can
   *  say where it meets the ground. */
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
      events: [`${name}(${x}, ${y}, left)`] })
      .then((r) => {
        //  A refusal is the allow-list doing its job, and silence about it is
        //  how you spend an afternoon wondering why clicking does nothing.
        if (r && r.refused && r.refused.length) onNote?.(`refused: ${r.refused.join(', ')}`);
      })
      .catch((e) => onNote?.(e.message));
  };

  const down = (e) => {
    if (e.button !== 0 || e.target.closest('.vp-controls')) return;
    dragging = at(e); send('lps_mousedown', dragging);
  };
  const move = (e) => {
    if (!dragging) return;
    const p = at(e);
    if (p[0] === dragging[0] && p[1] === dragging[1]) return;
    dragging = p; send('lps_mousedrag', p);
  };
  const up = (e) => { if (!dragging) return; send('lps_mouseup', at(e)); dragging = null; };

  view.addEventListener('pointerdown', down);
  view.addEventListener('pointermove', move);
  view.addEventListener('pointerup', up);
  view.addEventListener('pointercancel', up);
  return () => {
    view.removeEventListener('pointerdown', down);
    view.removeEventListener('pointermove', move);
    view.removeEventListener('pointerup', up);
    view.removeEventListener('pointercancel', up);
    view.style.cursor = '';
  };
}

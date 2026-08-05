/* viewport.js — one zoom-and-pan behaviour for every visualiser.
 *
 * §I.10.1a asks for controls that "appear as needed": wheel to zoom about the
 * pointer, drag to pan, double-click to reset, and a small cluster of buttons
 * that fades in on hover. The panes differ in what they draw, not in how they
 * are navigated, so this is written once and attached five times.
 *
 * It works on a transform, not on the drawing, so it is indifferent to whether
 * the pane rendered SVG, a Konva stage or a WebGL canvas. Renderers that own
 * their own camera (three.js) opt out and get the button cluster only.
 */

const clamp = (v, lo, hi) => Math.max(lo, Math.min(hi, v));

export class Viewport {
  /** @param {HTMLElement} host  the element to attach to (position: relative)
   *  @param {object} opts  { target: HTMLElement to transform, onChange, external }
   */
  constructor(host, opts = {}) {
    this.host = host;
    this.target = opts.target || host.firstElementChild;
    this.onChange = opts.onChange || null;
    this.external = !!opts.external;       // someone else owns the transform
    this.scale = 1; this.tx = 0; this.ty = 0;
    this.dragging = null;
    if (!this.external) this._attach();
    this._controls();
  }

  apply() {
    if (this.target && !this.external) {
      this.target.style.transformOrigin = '0 0';
      this.target.style.transform = `translate(${this.tx}px, ${this.ty}px) scale(${this.scale})`;
    }
    if (this.onChange) this.onChange({ scale: this.scale, x: this.tx, y: this.ty });
  }

  reset() { this.scale = 1; this.tx = 0; this.ty = 0; this.apply(); }

  zoomBy(factor, cx, cy) {
    const s = clamp(this.scale * factor, 0.1, 12);
    const k = s / this.scale;
    // keep the point under the cursor fixed
    this.tx = cx - k * (cx - this.tx);
    this.ty = cy - k * (cy - this.ty);
    this.scale = s;
    this.apply();
  }

  /* Fit, with a floor. A run of a dozen states laid out left to right is
   * several thousand pixels wide, and scaling that into a pane makes a
   * diagram nobody can read — the picture is technically complete and
   * practically useless. Below the floor we stop shrinking, align to the top
   * left, and let the user pan: a legible part of the graph beats an
   * illegible whole of it. */
  /*  `align` decides what to do with the room left over. Centring is right for
   *  a diagram, which is an object you look at, and wrong for a chart, which is
   *  read from the top left: a timeline 250 px tall in an 800 px pane was drawn
   *  as a band floating in the middle with 280 px of nothing above it, and read
   *  as "the pane failed to fill". */
  fit(contentW, contentH, minScale = 0.4, align = 'centre') {
    const r = this.host.getBoundingClientRect();
    if (!contentW || !contentH || !r.width || !r.height) return this.reset();
    const raw = Math.min(r.width / contentW, r.height / contentH) * 0.94;
    const s = clamp(Math.max(raw, Math.min(minScale, 1)), 0.05, 4);
    this.scale = s;
    const overflowX = contentW * s > r.width, overflowY = contentH * s > r.height;
    this.tx = overflowX ? 8 : (r.width - contentW * s) / 2;
    this.ty = (overflowY || align === 'top') ? 8 : (r.height - contentH * s) / 2;
    this.apply();
  }

  _attach() {
    this.host.addEventListener('wheel', (e) => {
      if (!e.ctrlKey && !e.metaKey && Math.abs(e.deltaY) < 2) return;
      e.preventDefault();
      const r = this.host.getBoundingClientRect();
      this.zoomBy(Math.exp(-e.deltaY * 0.0015), e.clientX - r.left, e.clientY - r.top);
    }, { passive: false });

    this.host.addEventListener('pointerdown', (e) => {
      if (e.button !== 0) return;
      const t = e.target;
      if (t.closest && t.closest('.vp-controls')) return;
      this.dragging = { x: e.clientX, y: e.clientY, tx: this.tx, ty: this.ty };
      this.host.setPointerCapture(e.pointerId);
      this.host.classList.add('vp-grabbing');
    });
    this.host.addEventListener('pointermove', (e) => {
      if (!this.dragging) return;
      this.tx = this.dragging.tx + (e.clientX - this.dragging.x);
      this.ty = this.dragging.ty + (e.clientY - this.dragging.y);
      this.apply();
    });
    const end = (e) => {
      if (!this.dragging) return;
      this.dragging = null;
      this.host.classList.remove('vp-grabbing');
      try { this.host.releasePointerCapture(e.pointerId); } catch { /* already gone */ }
    };
    this.host.addEventListener('pointerup', end);
    this.host.addEventListener('pointercancel', end);
    this.host.addEventListener('dblclick', () => this.reset());
  }

  _controls() {
    const box = document.createElement('div');
    box.className = 'vp-controls';
    const mk = (label, title, fn) => {
      const b = document.createElement('button');
      b.textContent = label; b.title = title;
      b.addEventListener('click', (e) => { e.stopPropagation(); fn(); });
      box.appendChild(b);
      return b;
    };
    const centre = () => {
      const r = this.host.getBoundingClientRect();
      return [r.width / 2, r.height / 2];
    };
    mk('+', 'Zoom in', () => this.zoomBy(1.25, ...centre()));
    mk('−', 'Zoom out', () => this.zoomBy(0.8, ...centre()));
    mk('⤢', 'Fit', () => { if (this.onFit) this.onFit(); else this.reset(); });
    this.host.appendChild(box);
    this.controlsEl = box;
  }
}

/** Convenience: wrap freshly rendered content in a pane and return the viewport. */
export function mountViewport(pane, node, { external = false, onFit = null } = {}) {
  pane.classList.add('vp-host');
  const wrap = document.createElement('div');
  wrap.className = 'vp-content';
  wrap.appendChild(node);
  pane.replaceChildren(wrap);
  const vp = new Viewport(pane, { target: wrap, external });
  vp.onFit = onFit;
  return vp;
}

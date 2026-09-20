/* boot.js — how a page that was written for a server finds there is none.
 *
 * The IDE talks to one endpoint: POST /lpsapi, a JSON object in and a JSON
 * object out — "anything on screen can be reproduced with curl", as
 * ui/src/api.js puts it. That is the whole of its dependence on a server, and
 * it is the reason this file is forty lines of interception rather than a fork
 * of the IDE: `fetch` is replaced before the page's own scripts run, and the
 * three addresses that need a server are answered from the worker instead.
 * Everything else — the bundle, the icons, the documentation — is a file on a
 * static host, and goes through untouched.
 *
 * It must be a classic <script> in <head>, before anything else: module
 * scripts are deferred, so a plain one in the head has already run by the time
 * they start, and nothing can capture the original `fetch` before this does.
 *
 * The configuration is `window.LPS_WASM_CONFIG`, set by config.js next to
 * this file (so that a deployment can change it without rebuilding the pages):
 *
 *     base     where the runtime's own files live      (default /lps-wasm/)
 *     build    what the status endpoint should report
 *     proxy    a same-origin address that will forward a request this page is
 *              not allowed to make (wasm/api/proxy.js); '' for none
 *     le       true when the payload carries a Logical English
 */
(function () {
    'use strict';
    var CFG = window.LPS_WASM_CONFIG = Object.assign({
        base: '/lps-wasm/',
        build: 'WebAssembly build',
        proxy: '',
        le: false,
        banner: true
    }, window.LPS_WASM_CONFIG || {});

    var nativeFetch = window.fetch.bind(window);
    var worker = null, nextId = 1, pending = new Map(), ready = false;

    function start() {
        if (worker) return worker;
        worker = new Worker(CFG.base + 'worker.js');
        worker.onmessage = function (event) {
            var msg = event.data || {};
            if (msg.kind === 'reply') {
                var resolve = pending.get(msg.id);
                pending.delete(msg.id);
                if (resolve) resolve(msg.json);
            } else if (msg.kind === 'ready') {
                ready = true;
                note('ready', msg);
            } else if (msg.kind === 'status') {
                note(msg.text, msg.detail);
            } else if (msg.kind === 'failed') {
                note('failed', msg);
            } else if (msg.kind === 'log' && msg.err) {
                console.warn('[lps-wasm]', msg.line);
            }
        };
        worker.postMessage({ kind: 'boot', config: CFG });
        return worker;
    }

    function ask(body) {
        var id = nextId++;
        return new Promise(function (resolve) {
            pending.set(id, resolve);
            start().postMessage({ kind: 'call', id: id, body: body });
        });
    }


    /*  Every reply, as a DOM event on the window.
     *
     *  On the server a reply is an HTTP response, and anything that wants to
     *  watch one — a test, a support session, the console — watches the
     *  network. Here it never reaches the network, so there would otherwise
     *  be nothing to watch at all. The event carries the operation's name and
     *  the reply text; it costs nothing when nobody is listening. */
    function announce(operation, text) {
        try {
            window.dispatchEvent(new CustomEvent('lps-api-reply', {
                detail: { operation: operation, reply: text }
            }));
        } catch (e) { /* an old browser: the page is unaffected */ }
    }

    function json(text, status) {
        return new Response(text, {
            status: status || 200,
            headers: { 'Content-Type': 'application/json' }
        });
    }

    /*  The addresses a server answered and a static host cannot.
     *
     *  /lpsapi is the one that matters; the other two are what the IDE asks
     *  about the server it thinks it has — which build, and whether Logical
     *  English is configured — and answering them here is what keeps it from
     *  offering a door that opens on nothing. */
    function intercept(url, init) {
        var path = url.split('?')[0];
        if (path === '/lpsapi' || path.endsWith('/lpsapi')) {
            var body = {};
            try { body = JSON.parse((init && init.body) || '{}'); } catch (e) { /* let Prolog say so */ }
            return ask(JSON.stringify(body)).then(function (text) {
                announce(body.operation, text);
                return json(text);
            });
        }
        if (path === '/lpsapi/status') {
            /*  What the IDE asks before anything else. `le` is the answer that
             *  changes what it shows: a build with no Logical English in it
             *  does not offer to open a .le. */
            return Promise.resolve(json(JSON.stringify({
                ok: true, build: CFG.build, wasm: true,
                le: CFG.le === true ? 'lib' : 'none',
                token: false
            })));
        }
        if (path === '/telemetry_test') {
            return Promise.resolve(json(JSON.stringify({ ok: false, reason: 'no server in the WebAssembly build' })));
        }
        return null;
    }

    window.fetch = function (input, init) {
        var url = typeof input === 'string' ? input
                : (input && input.url) ? input.url : String(input);
        var options = init;
        if (input && typeof input !== 'string' && input.method) {
            /* a Request object: the body is a stream, so read it the way the
             * one caller that does this (none, today) would need. */
            options = init || { method: input.method };
        }
        var handled = null;
        try { handled = intercept(url, options); } catch (e) { handled = null; }
        return handled || nativeFetch(input, init);
    };

    /* ------------------------------------------------------------ the sign */

    /*  Booting takes a few seconds the first time — a 2 MB runtime, a 1 MB
     *  payload, and four hundred files unpacked — and a page that looks
     *  finished but answers nothing is worse than one that says what it is
     *  doing. The banner removes itself, and a deployment that would rather
     *  not have it sets `banner: false`. */
    var bar = null;
    function note(text, detail) {
        if (!CFG.banner) return;
        if (text === 'ready') {
            if (bar) {
                bar.textContent = 'LPS2 is running in this browser'
                    + (detail && detail.ms ? ' (started in ' + (detail.ms / 1000).toFixed(1) + 's)' : '');
                bar.style.background = '#e8f4e8';
                setTimeout(function () { if (bar) { bar.style.transition = 'opacity .6s'; bar.style.opacity = '0'; } }, 2500);
                setTimeout(function () { if (bar && bar.parentNode) bar.parentNode.removeChild(bar); bar = null; }, 3300);
            }
            return;
        }
        if (text === 'failed') {
            if (!bar) bar = makeBar();
            bar.style.background = '#fde8e8';
            bar.textContent = 'The LPS2 engine could not start: ' + (detail && detail.message || '');
            return;
        }
        if (!bar) bar = makeBar();
        bar.textContent = text;
    }

    function makeBar() {
        var el = document.createElement('div');
        el.setAttribute('role', 'status');
        el.style.cssText = 'position:fixed;z-index:2147483647;left:0;right:0;bottom:0;'
            + 'padding:6px 12px;font:12px/1.4 system-ui,-apple-system,sans-serif;'
            + 'background:#eef2f7;color:#333;border-top:1px solid #cfd8e3;text-align:center';
        (document.body || document.documentElement).appendChild(el);
        return el;
    }

    /*  Start now — not on the first request, and not at DOMContentLoaded.
     *  This script runs in <head>, before the page's own module scripts have
     *  been fetched, so the engine's 3 MB and the page's own downloads
     *  overlap instead of queueing. The banner is the only part that needs a
     *  document, and it makes one when it has one. */
    start();
    window.LPS_WASM = {
        call: ask,
        isReady: function () { return ready; },
        worker: function () { return worker; }
    };
}());

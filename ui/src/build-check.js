/* build-check.js — is this page of the same build as this script?
 *
 * A page and its script are two files, and a browser can pair an old one with
 * a new one: a tab that the browser brings back from its cache gets the page
 * as it was days ago, and the script as the server has it now. The script then
 * asks the page for an element that the page never had, and nothing appears
 * (Sentry, 2026-11-22: the editor, and its `composite events` box, one build
 * after the box was added).
 *
 * The build writes one stamp into both (ui/build.mjs): the page carries it as
 * `<html data-build="…">`, the script has it compiled in as `__LPS_BUILD__`.
 * When the two differ the page is loaded again, which asks the server for
 * both. Once only for each address, so that a copy that will not go away
 * cannot make the page reload for ever.
 */

/** True when the page may be used. False when the page is being loaded again:
 *  the caller must then do nothing more. */
export function pageIsOfThisBuild() {
  if (document.documentElement.dataset.build === __LPS_BUILD__) return true;
  const key = 'lps.reloaded-for-build:' + location.pathname;
  try {
    if (sessionStorage.getItem(key) === __LPS_BUILD__) return true;
    sessionStorage.setItem(key, __LPS_BUILD__);
  } catch { return true; /* no storage to count the reload in: do not risk a loop */ }
  location.reload();
  return false;
}

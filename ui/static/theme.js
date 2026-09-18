/* theme.js — the theme the IDE is on, for the pages that are not the IDE.
 *
 * The documentation viewer, its search page and the live view are opened
 * *from* the IDE (Help, a documentation link, the Live panel), and each of
 * them used to carry `data-theme="dark"` in its markup and nothing that ever
 * changed it: a user on the light theme searched the documentation and got a
 * dark page. The setting is the IDE's own (main.js writes `lps.theme`), so
 * read it here rather than guessing from the system's preference.
 *
 * Loaded as the first thing in the body, before the page has anything to
 * paint, and it follows a theme change made in the IDE while this page is
 * open (a `storage` event is what another tab's write looks like).
 */
(function () {
  function apply() {
    try {
      var t = JSON.parse(localStorage.getItem('lps.theme') || '"lps-dark"');
      document.body.dataset.theme = (t === 'lps-light') ? 'light' : 'dark';
    } catch (e) { /* private mode, or no storage: the markup's default stands */ }
  }
  apply();
  window.addEventListener('storage', function (e) {
    if (!e.key || e.key === 'lps.theme') apply();
  });
}());

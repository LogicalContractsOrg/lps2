/* lps_http.pl — the HTTP surface (§I.8.2).

   One POST endpoint dispatching on an `operation` field, with token auth —
   the LE2 pattern, deliberately, because it already works and the IDE will
   be a client of both.

     compile      source + syntax (+ provenance) → program id + diagnostics
     session_new  program id → session id
     observe      inject events into a session
     step / run   advance one/several cycles, return CycleReports
     state        current fluents
     fork         open a hypothetical branch (§I.6)
     discard      drop one
     trace        the full trace, for the timeline UI
     dump         the internal syntax
     analyse      compile only, and return diagnostics with source positions —
		  the LSP round trip of §I.10.1
     example      the text of a shipped example, by name
     resource     where an `includes these resources:` item of a document leads
     explain      the five question forms of §I.10.5
     timeline     lanes and intervals for §I.10.2
     changes      the state-change diagram of §I.10.3
     scene        the display/2 visual mapping for a cycle (§I.10.4)
     automaton    the state-transitions diagram of the run (godfa/1)

   `POST /mcp` is beside it and is not an operation of this endpoint: it is the
   Model Context Protocol surface (src/edges/lps_mcp.pl), whose envelope the
   protocol fixes. It is here because an agent and the IDE should reach one
   running server, and because a live session is the one world both can hold.

   `compile` and `analyse` accept an optional `provenance` array alongside a
   `syntax: "internal"` source: one entry per source term, in term order,
   `{index, file, line, col, kind}`. That is how an LE-authored program
   (docs/dev/le-lps-interface.md) gets its diagnostics reported at `.le`
   coordinates rather than at lines of the internal text LE2 generated.

   This is an *edge*: it may use threads freely, and does — the HTTP server is
   threaded. The core contract stays synchronous (`lps_session_step/3`), so a
   single-threaded deployment remains possible without changing a line of
   engine code — and one exists: the WebAssembly build of wasm/, which serves
   the same IDE from a page with no server under it.

   The operations themselves are **not here**. They are lps_api.pl, which has
   no HTTP in it, so that the browser build can call the same handle/2 this
   file calls. What stays here is the server: the routes, the pages, the
   assets, the token, and the MCP endpoint's envelope.

   Cross-session isolation is structural, not module-based as it was upstream:
   two sessions are two terms in a registry, sharing one immutable program.
   Nothing one session does can be seen by another, which is what makes
   multi-program/multi-session safe rather than merely conventional.
*/

:- module(lps_http, [
	lps_server/1,            % +Port
	lps_server/2,            % +Port, +Options
	lps_stop/1               % +Port
	]).

:- use_module(library(http/thread_httpd)).
:- use_module(library(http/html_write)).
:- use_module(library(http/http_dispatch)).
:- use_module(library(http/http_files)).
:- use_module(library(http/http_path)).
:- use_module(library(filesex)).
:- use_module(library(time)).
:- use_module(library(http/http_json)).
:- use_module(library(http/json)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(yall)).
:- use_module('../core/lps_ops').
:- use_module('../core/lps_diag').
:- use_module('../core/lps_session').
:- use_module('../core/lps_program').
:- use_module('../syntax/lps_internal_syntax').
:- use_module('../core/lps_explain').
:- use_module(lps_source).
:- use_module(lps_le).
:- use_module(lps_sandbox).
:- use_module(lps_assistant).
:- use_module(lps_live).
:- use_module(lps_play).
:- use_module('../syntax/lps_inform').
:- use_module(lps_wasm).
:- use_module(lps_models).
:- use_module(lps_ids).
:- use_module('../syntax/lps_pddl').
:- use_module('../syntax/lps_plus').
:- use_module('../syntax/lps_surface_write').
:- use_module(lps_telemetry).
:- use_module(lps_mcp).
:- use_module(lps_api).

:- dynamic auth_token/1.


:- http_handler('/lpsapi', lpsapi, [methods([post, options])]).
:- http_handler('/lpsapi/status', api_status, [methods([get, options])]).
:- http_handler('/mcp', mcp_endpoint, [methods([post, get, options])]).
:- http_handler('/', landing_page, []).
:- http_handler('/ide', ide_page, []).
%  The sector pages, one short address each (it is what a leaflet's QR code
%  says): sector_page/2, below. A new sector is a row here and a file there.
:- http_handler('/insurance', sector_page(insurance), []).
%  The browser asks for this on every page; without it each visit logged
%  a 404 in the console. The mark is ui/static/favicon.svg, built into dist/.
:- http_handler('/favicon.ico', favicon, []).
:- http_handler('/', ide_page, [prefix]).
:- http_handler('/docs/', docs_page, [prefix]).
:- http_handler('/docs-raw/', docs_raw, [prefix]).
:- http_handler('/assets/', ide_asset, [prefix]).
%  Error reports and analytics, when the environment configures them
%  (lps_telemetry.pl, docs/dev/telemetry.md): every page loads /telemetry.js.
:- http_handler('/telemetry.js', telemetry_script, []).
:- http_handler('/telemetry_test', telemetry_check, []).
%  Signing in: one sign-in for this server and Logical English's, kept in the
%  private lpsPlus repository (src/syntax/lps_plus.pl, lps_plus_accounts/0).
%  /login offers Google, GitHub and a password; /auth/... are lpsPlus's own
%  routes for the first two.
:- http_handler('/login', login_page, []).
:- http_handler('/logout', logout, []).
:- http_handler('/whoami', whoami, [methods([get])]).

%  Every request, before its handler: who sent it, and so what it may use
%  (lps_plus_identify/1).
:- http_request_expansion(identify_visitor, 10).

identify_visitor(Request, Request, _Options) :-
	lps_plus_identify(Request).

accounts_here :- current_predicate(lc_accounts:lc_login_page/2).

%	The landing page's top-right corner: who is signed in, and the way in or
%	out. Nothing on a server without lpsPlus's sign-in. A term computed here,
%	not a conditional inside the page (html_write would read it as HTML).
sign_in_corner(Corner) :-
	(   \+ lps_api:sign_in_offered
	->  Corner = ''
	;   lps_plus_visitor(Email, _)
	->  Corner = div(class('sign-in'), [span(Email), ' ', a(href('/logout'), 'Sign out')])
	;   Corner = div(class('sign-in'), a(href('/login?return=/'), 'Sign in'))
	).

login_page(Request) :-
	(   lps_api:sign_in_offered
	->  lc_accounts:lc_login_page(Request, [head([script([src('/telemetry.js')], [])])])
	;   %  A clone, or a server whose sign-in is not configured: say so,
	    %  rather than offer a form no account can satisfy. Everything the
	    %  editor does works without signing in.
	    reply_html_page([title('Sign in')],
			    [h1('Sign in'),
			     p('This server has no sign-in. Every feature of the editor works without one; signing in is for the licences of the hosted service.'),
			     p(a(href('/'), 'Back to the start page'))])
	).

logout(Request) :-
	(   accounts_here
	->  lc_accounts:lc_safe_return(Request, '/', Return),
	    lc_accounts:lc_sign_out_reply(Request, Return)
	;   throw(http_reply(moved_temporary('/')))
	).

/*  The visitor, for the IDE's sign-in corner: `loggedIn`, `email`, and the
    `licenses` and `capabilities` held today. */
whoami(Request) :-
	(   lps_api:sign_in_offered
	->  lc_accounts:lc_whoami(Request, Reply)
	;   Reply = _{loggedIn: false, email: null, licenses: [], capabilities: []}
	),
	reply_json_dict(Reply).

/* The IDE (§I.10.1a, M14). Built by `npm --prefix ui run build` into
   src/ide/dist/ and served from here — the engine still has no build step and
   still needs no Node at run time, but Monaco, Konva and three.js are not
   things you paste into a page.

   Everything under dist/ is served flat, because that is what the bundler
   emits and what the page's own relative URLs ask for.
*/
ide_page(Request) :-
	memberchk(path(Path), Request),
	(   ( Path == '/' ; Path == '/ide' ; Path == '/ide/' )
	->  ide_dist_file('index.html', File), serve_file(File)
	;   atom_concat('/', Rel, Path),
	    ide_dist_file(Rel, File)
	->  serve_file(File)
	;   throw(http_reply(not_found(Path)))
	).

/*  The pages' telemetry script (lps_telemetry.pl): one line that loads
    nothing unless Sentry or Web Analytics is configured. */
telemetry_script(_Request) :-
	telemetry_js(JS),
	format('Content-type: text/javascript; charset=UTF-8~n'),
	format('Cache-Control: no-cache~n~n'),
	write(JS).

telemetry_check(_Request) :-
	telemetry_test(Reply),
	reply_json_dict(Reply).

		 /*******************************
		 *	   the sector pages	*
		 *******************************/

/*  A page for one market: what a printed leaflet's QR code opens, saying what
    the leaflet says and leading on to the documents and examples that show it.
    Each is a file, src/pages/<Sector>.html, complete in itself (its styles and
    its logo are in it), so the route is all the server adds — and the telemetry
    script, which serve_file/1 puts in every HTML page, so that visits are
    counted where analytics are configured. The drawing in a page is written
    into it by lpsPlus's docs/sales/leaflets/build.cjs, from the leaflet's own
    source; the words are the page's.
*/
sector_page(Sector, Request) :-
	(   sector_page_file(Sector, File)
	->  serve_file(File)
	;   memberchk(path(Path), Request),
	    throw(http_reply(not_found(Path)))
	).

%	Where a sector's page is. The pages are Logical Contracts' own — what
%	its leaflets say, with its telephone number — so they live with the
%	leaflets, in lpsPlus (docs/sales/pages/), and a server has them only
%	when it has that checkout beside it or vendored in (tools/vendor_lpsplus.sh):
%	the hosted service does, a clone of this repository does not, and
%	answers /insurance with 404. A file under src/pages/ is still honoured,
%	for a deployment that keeps its own.
sector_page_file(Sector, File) :-
	lps_root(Root),
	(   atomic_list_concat([Root, '/src/pages/', Sector, '.html'], File),
	    exists_file(File)
	->  true
	;   lps_plus_root(Plus),
	    atomic_list_concat([Plus, '/docs/sales/pages/', Sector, '.html'], File),
	    exists_file(File)
	).

favicon(_Request) :-
	(   ide_dist_file('favicon.svg', File)
	->  serve_file(File)
	;   throw(http_reply(not_found('/favicon.ico')))
	).

		 /*******************************
		 *	   the landing page	*
		 *******************************/

/*  What `/` is now. The IDE opens on an empty buffer, which is the right thing
    for somebody who already has a program and the wrong thing for everybody
    else: the corpus is the documentation, and until now the only way in was a
    modal dialog behind a menu, showing one flat list of two hundred names.

    So: a page. It is server-rendered, like LE2's (`classic_web_api.pl`,
    `handle_landing_page/1`), and takes the same shape — collapsible folders
    keyed by path, their open/closed state kept in LocalStorage so the tree you
    left is the tree you come back to, `?expand=all` to open everything, and
    the documents beside the programs. The IDE moved to /ide, and every example
    here links into it.
*/
landing_page(_Request) :-
	sign_in_corner(Corner),
	example_tree(Tree),
	build_stamp(Stamp),
	tree_html(Tree, '', Items),
	%  The *contents*, not the predicate names: `style(landing_css)` puts the
	%  atom `landing_css` in the page, which is a stylesheet saying nothing and
	%  a script that never ran.
	landing_css(CSS), landing_js(JS), landing_readme_js(ReadmeJS),
	reply_html_page(
	    [ title('Logic Production Systems 2'),
	      link([rel(icon), type('image/svg+xml'), href('/favicon.svg')]),
	      meta([name(viewport), content('width=device-width, initial-scale=1')]),
	      script([src('/telemetry.js')], []),
	      style(CSS),
	      script([type('text/javascript')], \['\n', JS]),
	      script([type('text/javascript')], \['\n', ReadmeJS])
	    ],
	    [ Corner,
	      h1('Logic Production Systems 2'),
	      p(class(sub),
		[ 'A new implementation of the LPS engine in SWI-Prolog. It ',
		  'reproduces the earlier engine\'s own recorded test runs, ',
		  'cycle for cycle. ',
		  span(class(muted), ['Build ', Stamp])
		]),
	      div(class(cols),
		  [ div(class(col),
			[ h2([ 'Examples ',
			       span([id(controls), style('display:none')],
				    [ '(', a([href('#'), id(expandall)], 'expand all'),
				      ' · ', a([href('#'), id(collapseall)], 'collapse all'),
				      ')' ]) ]),
			  ul(class(tree), Items)
			]),
		    div(class(col),
			[ h2('Start'),
			  ul(class(plain),
			     [ li(a([href('/ide'), class(primary)], 'Open the IDE')),
			       li([ a(href('/ide?example=start/goat_declarative'),
				      'Open the wolf, goat and cabbage'),
				    span(class(muted), ' — the whole language on one page') ])
			     ]),
			  h2('Documentation'),
			  form([action('/docs/search'), method(get), role(search), class(docsearch)],
			       [ input([type(search), name(q), placeholder('Search the documentation'),
					'aria-label'('Search the documentation')]),
				 ' ', input([type(submit), value('Search')]) ]),
			  ul(class(plain), \landing_docs)
			])
		  ])
	    ]).

landing_docs -->
	{ findall(li([ a([href(Href), target('_blank')], Title),
		       br([]), span(class(muted), Blurb) ]),
		  landing_doc(Href, Title, Blurb), Items) },
	html(Items).

%	The documents docs/user/nav.json (the documentation's table of
%	contents, which the Help menu and the viewer read too) marks `landing`.
landing_doc(Href, Title, Blurb) :-
	doc_nav(Nav),
	member(Section, Nav.sections),
	member(Item, Section.items),
	get_dict(landing, Item, true),
	atom_concat('/docs/user/', Item.path, Href),
	Title = Item.title,
	Blurb = Item.blurb.

doc_nav(Nav) :-
	lps_root(Root),
	atomic_list_concat([Root, '/docs/user/nav.json'], File),
	catch(setup_call_cleanup(open(File, read, In, [encoding(utf8)]),
				 json_read_dict(In, Nav),
				 close(In)), _, fail).

/*!	example_tree(-Tree) is det.

	`folder(Label, Path, Children)` and `leaf(Name, Title)`, from the same
	`example_list/1` the picker uses — so the page and the dialog can never
	disagree about what is shipped.

	The nesting comes from the real directory paths, not from the display
	labels: `legacy_lps1/examples/CLOUT_workshop/simulation` belongs *inside*
	`.../CLOUT_workshop`, and a flat list of labels cannot say so. A
	directory's parent is the longest other example directory that is a
	prefix of it.  */
example_tree(Tree) :-
	example_list(Examples),
	findall(Dir-e(Name, Title),
		( member(E, Examples),
		  get_dict(name, E, Name), get_dict(dirpath, E, Dir),
		  ( get_dict(title, E, Title) -> true ; Title = '' ) ),
		Pairs),
	keysort(Pairs, Sorted),
	group_pairs_by_key(Sorted, Groups),
	findall(Dir, example_dir(Dir, _), Dirs),
	findall(D, ( member(D, Dirs), \+ dir_parent(D, Dirs, _) ), Roots),
	findall(F, ( member(R, Roots), dir_folder(R, Dirs, Groups, F) ), Tree0),
	sort_folders(Tree0, Tree).

%	The longest listed directory that is a proper prefix of Dir.
dir_parent(Dir, Dirs, Parent) :-
	findall(L-D, ( member(D, Dirs), D \== Dir,
		       atom_concat(D, '/', DS), atom_concat(DS, _, Dir),
		       atom_length(D, L) ), Cands),
	Cands \== [],
	sort(0, @>=, Cands, [_-Parent|_]).

dir_folder(Dir, Dirs, Groups, folder(Label, Dir, Children)) :-
	( example_dir(Dir, Label) -> true ; file_base_name(Dir, Label) ),
	( memberchk(Dir-Es, Groups) -> true ; Es = [] ),
	findall(leaf(N, T), member(e(N, T), Es), Leaves),
	findall(Sub, ( member(D, Dirs), dir_parent(D, Dirs, Dir),
		       dir_folder(D, Dirs, Groups, Sub) ), Subs1),
	sort_folders(Subs1, Subs0),
	%  A directory with nothing in it and nothing under it is not worth a row.
	exclude(empty_folder, Subs0, Subs),
	append(Leaves, Subs, Children).

empty_folder(folder(_, _, [])).

%	LPS2's own examples first, then the doors (PDDL, Drools), then the
%	corpus: the order somebody meeting the system should meet them in.
sort_folders(Fs, Sorted) :-
	findall(R-F, ( member(F, Fs), F = folder(L, _, _), folder_rank(L, R) ), Ranked),
	keysort(Ranked, S), pairs_values(S, Sorted).

folder_rank(L, R-'') :-
	nth0(R, ['LPS2', 'Start here', 'Logical English', 'Interactive fiction',
		 'Planning', 'Agents', 'Collections', 'Migration twins'], L), !.
folder_rank('corpus', 8-'') :- !.
folder_rank(L, 9-L).

tree_html([], _, []).
tree_html([folder(Label, Path, Children)|Rest], Prefix, [Item|Items]) :-
	%  Path is already the full directory path, and it is what LocalStorage
	%  is keyed by — so it must not have the parent's prefix stuck in front
	%  of it a second time.
	FullPath = Path,
	%  The count is of programs, here and below — a folder holding only
	%  folders should not read as empty.
	leaf_count(Children, N),
	tree_html_children(Children, Prefix, ChildItems),
	folder_readme_src(FullPath, ReadmeSrc),
	Item = li(class('folder-item'),
		  details(['data-path'(FullPath), class(folder)],
			  [ summary([b(Label), span(class(count), [' ', N])]),
			    ReadmeSrc,
			    ul(ChildItems) ])),
	tree_html(Rest, Prefix, Items).

leaf_count([], 0).
leaf_count([leaf(_, _)|T], N) :- !, leaf_count(T, N0), N is N0 + 1.
leaf_count([folder(_, _, C)|T], N) :- leaf_count(C, N1), leaf_count(T, N2), N is N1 + N2.

%	A title of spaces is no title.
blank(T) :- ( T == '' ; T == "" ), !.
blank(T) :- normalize_space(atom(''), T).

tree_html_children([], _, []).
tree_html_children([leaf(Name, Title)|Rest], Prefix, [Item|Items]) :- !,
	format(atom(Href), '/ide?example=~w', [Name]),
	( blank(Title) -> Extra = [] ; Extra = [span(class(muted), [' — ', Title])] ),
	Item = li([a(href(Href), Name)|Extra]),
	tree_html_children(Rest, Prefix, Items).
tree_html_children([F|Rest], Prefix, [Item|Items]) :-
	tree_html([F], Prefix, [Item]),
	tree_html_children(Rest, Prefix, Items).

/*!	folder_readme_src(+Dir, -Element) is det.

	A folder's README.md, as hidden text on the landing page, for the panel
	that shows it beside the list (src/edges/readme_panel.js): keyed by the
	folder's data-path, with the prefix of its examples' names (relative to
	examples/, as example_rel/3 forms them) and its path in the repository,
	which the panel needs to make the README's relative links open the
	programs they name. The empty atom when the folder has no README.  */
folder_readme_src(Dir, Element) :-
	lps_root(Root),
	atomic_list_concat([Root, '/', Dir, '/README.md'], Readme),
	(   exists_file(Readme),
	    catch(read_file_to_string(Readme, Text, [encoding(utf8)]), _, fail)
	->  (   atom_concat('examples/', Sub, Dir) -> atom_concat(Sub, '/', Name)
	    ;   Name = ''
	    ),
	    Element = div([class('readme-src'), hidden(hidden), 'data-for'(Dir),
			   'data-name'(Name), 'data-repo'(Dir)], Text)
	;   Element = ''
	).

/*	The panel that shows a folder's README: src/edges/readme_panel.js, the
	same file as LE2's web_extras/landing/readme-panel.js, after its
	settings. A program opens in the IDE by its file name, extension and all
	(example_source/3 takes it): without it, `trolley.lps` would open its
	Logical English sibling `trolley.le`. Any other file of the repository
	opens on GitHub.  */
landing_readme_js(JS) :-
	lps_root(Root),
	atomic_list_concat([Root, '/src/edges/readme_panel.js'], File),
	(   catch(read_file_to_string(File, Panel, [encoding(utf8)]), _, fail)
	->  true
	;   Panel = ""
	),
	format(atom(JS), 'window.EXAMPLE_README = { folders: "details.folder[data-path]", \c
editor: "/ide?example=", programs: [], keepExt: ["lps", "pl", "le", "pddl", "drl", "ni"], \c
source: "https://github.com/LogicalContractsOrg/lps2/blob/main/", about: "About this folder", close: "Close", \c
copy: "Copy the web address of this README", copied: "Copied" };~n~w',
	       [Panel]).

build_stamp(Stamp) :-
	(   ide_dist_file('BUILD.txt', F),
	    read_file_to_string(F, S, [encoding(utf8)])
	->  normalize_space(atom(Stamp), S)
	;   Stamp = 'dev'
	).

landing_css('
:root { color-scheme: light dark; }
body { font: 15px/1.5 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
       margin: 0 auto; max-width: 1100px; padding: 24px 20px 60px; }
h1 { font-size: 26px; margin: 0 0 4px; }
.sign-in { float: right; font-size: 14px; }
h2 { font-size: 15px; text-transform: uppercase; letter-spacing: .06em;
     margin: 26px 0 8px; opacity: .75; }
p.sub { margin: 0 0 8px; }
.muted { opacity: .6; }
.cols { display: flex; gap: 40px; align-items: flex-start; flex-wrap: wrap; }
.col:first-child { flex: 2 1 460px; min-width: 0; }
.col:last-child  { flex: 1 1 280px; }
ul { margin: 0; padding-left: 18px; }
ul.tree, ul.plain { list-style: none; padding-left: 0; }
ul.tree ul { list-style: none; padding-left: 18px; }
ul.plain li { margin-bottom: 10px; }
li.folder-item { list-style: none; }
details.folder > summary { cursor: pointer; padding: 3px 0; user-select: none; }
details.folder > summary:hover { opacity: .8; }
.count { opacity: .45; font-size: 12px; }
a.folder-link { margin-left: 6px; font-size: 12px; opacity: .45; border-bottom: none; }
a.folder-link:hover, a.folder-link.copied { opacity: 1; }
details.folder-target > summary { background: rgba(255, 200, 0, .25); }
a { color: inherit; }
a.primary { font-weight: 600; }
li a { text-decoration: none; border-bottom: 1px solid transparent; }
li a:hover { border-bottom-color: currentColor; }
@media (prefers-color-scheme: dark) { body { background: #1e1e1e; color: #d4d4d4; } }
').

/*  The folder state, remembered. Straight from LE2's landing_folders_script/1
    — same behaviour, same LocalStorage-per-folder shape, different prefix so
    the two servers can share a browser without sharing a tree. Also as in
    LE2: a link symbol after each folder's name copies the web address of the
    folder (`/?dir=<its path>`; the symbol is a real link, so the browser's
    own "Copy link" works too), and opening that address opens the folder and
    those around it and scrolls to it.  */
landing_js('(function(){
  "use strict";
  var P = "lps-folder:";
  var TIP = "Copy the web address of this folder", DONE = "Copied";
  function folders(){
    return Array.prototype.slice.call(document.querySelectorAll("details.folder[data-path]"));
  }
  function save(f){
    var p = f.getAttribute("data-path");
    if (!p) return;
    try { window.localStorage.setItem(P + p, f.open ? "1" : "0"); } catch (e) {}
  }
  function setAll(open){ folders().forEach(function(f){ f.open = open; save(f); }); }
  function wantAll(){
    var v = new URLSearchParams(window.location.search).get("expand");
    return v === "all" || v === "1" || v === "true";
  }
  function folderPath(f){ return (f.getAttribute("data-path") || "").replace(/\\/+$/, ""); }
  function folderUrl(f){
    var u = new URL(window.location.href);
    u.hash = "";
    u.searchParams.delete("expand");
    u.searchParams.set("dir", folderPath(f));
    return u.toString();
  }
  function copyText(text, done){
    function fallback(){
      var ta = document.createElement("textarea");
      ta.value = text; ta.setAttribute("readonly", "");
      ta.style.position = "fixed"; ta.style.opacity = "0";
      document.body.appendChild(ta); ta.select();
      try { if (document.execCommand("copy")) done(); } catch (e) {}
      document.body.removeChild(ta);
    }
    if (navigator.clipboard && window.isSecureContext) {
      navigator.clipboard.writeText(text).then(done, fallback);
    } else { fallback(); }
  }
  function addLink(f){
    var s = f.querySelector("summary"), title = s ? s.querySelector("b") : null;
    if (!title) return;
    var a = document.createElement("a");
    a.className = "folder-link";
    a.href = folderUrl(f);
    a.title = TIP; a.setAttribute("aria-label", TIP);
    a.textContent = "\\u{1F517}";
    a.addEventListener("click", function(e){
      e.preventDefault(); e.stopPropagation();
      copyText(a.href, function(){
        a.textContent = DONE; a.classList.add("copied");
        setTimeout(function(){ a.textContent = "\\u{1F517}"; a.classList.remove("copied"); }, 1500);
      });
    });
    title.insertAdjacentElement("afterend", a);
  }
  function reveal(all){
    var d = new URLSearchParams(window.location.search).get("dir");
    if (!d) return;
    d = d.replace(/\\/+$/, "");
    var f = all.filter(function(x){ return folderPath(x) === d; })[0];
    if (!f) return;
    for (var p = f; p; p = p.parentElement ? p.parentElement.closest("details") : null) p.open = true;
    f.classList.add("folder-target");
    f.scrollIntoView({ block: "start" });
  }
  function init(){
    var all = folders(), openAll = wantAll();
    var controls = document.getElementById("controls");
    if (controls && all.length) controls.style.display = "";
    all.forEach(function(f, i){
      if (openAll) { f.open = true; }
      else {
        var s = null;
        try { s = window.localStorage.getItem(P + f.getAttribute("data-path")); } catch (e) {}
        f.open = s === null ? i === 0 : s === "1";
      }
      f.addEventListener("toggle", function(){ save(f); });
    });
    if (openAll) all.forEach(save);
    all.forEach(addLink);
    reveal(all);
    var ex = document.getElementById("expandall");
    if (ex) ex.addEventListener("click", function(e){ e.preventDefault(); setAll(true); });
    var co = document.getElementById("collapseall");
    if (co) co.addEventListener("click", function(e){ e.preventDefault(); setAll(false); });
  }
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", init);
  else init();
})();').

ide_asset(Request) :-
	memberchk(path(Path), Request),
	atom_concat('/assets/', Rel, Path),
	(   ide_dist_file(Rel, File)
	->  serve_file(File)
	;   throw(http_reply(not_found(Path)))
	).

%	`/docs/user/reference/lps` is the Help menu's target: the shell page, which
%	then fetches the markdown from /docs-raw/. LE2 serves its documents the
%	same way, and the container already carries docs/.
/*  A document's own pictures, and any other file under docs/user/ asked for by
    name with its extension. `docs/user/tutorials/lps-tutorial.md` says
    `![…](../images/ide-overview.png)`, which the browser resolves against the
    page's address; without this every image would be answered with the
    document *shell*, with a 200, so nothing would complain. */
docs_page(Request) :-
	memberchk(path(Path), Request),
	atom_concat('/docs/', Rel, Path),
	file_name_extension(_, Ext, Rel), Ext \== '', Ext \== md, !,
	(   public_doc(Rel), safe_name(Rel, Safe)
	->  lps_root(Root),
	    atomic_list_concat([Root, '/docs/', Safe], Full),
	    (   exists_file(Full)
	    ->  serve_file(Full)
	    ;   throw(http_reply(not_found(Path)))
	    )
	;   throw(http_reply(not_found(Path)))
	).
%	A document's old address (before docs/ was reorganised) redirects.
docs_page(Request) :-
	memberchk(path(Path), Request),
	atom_concat('/docs/', Old, Path),
	doc_moved(Old, New), !,
	atom_concat('/docs/', New, To),
	http_redirect(moved, To, Request).
docs_page(Request) :-
	memberchk(path(Path), Request),
	atom_concat('/docs/', Name, Path),
	(   Name == '' -> Doc = 'user/reference/lps' ; Doc = Name ),
	%  `search` is the documentation's search page (ui/static/docs-extras.js).
	(   ( public_doc(Doc) ; Doc == search ) -> true ; throw(http_reply(not_found(Path))) ),
	(   ide_dist_file('doc.html', File)
	->  read_file_to_string(File, Html0, [encoding(utf8)]),
	    /*  The shell reads window.LPS_DOC; putting the name in the page
	        rather than in the query string keeps the Help links plain.

	        A *JavaScript* string, not `~q`. `~q` quotes for Prolog, and
	        `lps_tutorial` is a perfectly good Prolog atom needing none — so
	        the page emitted `window.LPS_DOC=lps_tutorial;`, which is a
	        reference to an undefined variable, and the whole inline script
	        threw. The viewer then fell back to its default and served the
	        language reference under every lowercase document's URL.
	        `UsingTheIDE` worked by accident: it starts with a capital, so
	        Prolog quoted it and JavaScript got a string. */
	    safe_name(Doc, SafeDoc),
	    format(atom(Inject), '<script>window.LPS_DOC="~w";</script><script src="/telemetry.js"></script>', [SafeDoc]),
	    ( sub_atom(Html0, B, _, A, '</head>')
	    ->  sub_atom(Html0, 0, B, _, Pre), sub_atom(Html0, _, A, 0, Post),
	        atomic_list_concat([Pre, Inject, '</head>', Post], Html)
	    ;   Html = Html0 ),
	    format('Content-type: text/html; charset=UTF-8~n~n'),
	    write(Html)
	;   throw(http_reply(not_found(Path)))
	).

%!	public_doc(+Name) is semidet.
%
%	Name (with or without `.md`) is a document the server publishes: the
%	user documentation and what it links to. Plans, reviews and private
%	notes stay in the repository (LogicalEnglish2
%	docs/project/plans/NewDocumentationStructure.md §1.3): only docs/user/.
public_doc(Name) :-
	sub_atom(Name, 0, _, _, 'user/').

%!	doc_moved(?Old, ?New) is nondet.
%
%	The documents' addresses before docs/ was reorganised.
doc_moved(lps_summary, 'user/reference/lps').
doc_moved(lps_tutorial, 'user/tutorials/lps-tutorial').
doc_moved(glossary, 'user/reference/glossary').
doc_moved('UsingTheIDE', 'user/guide/ide').
doc_moved('IntroducingLPS2', 'user/overview/introducing-lps2').
doc_moved('LPS2abstract', 'user/overview/abstract').
doc_moved('LPSForInformUsers', 'user/tutorials/inform-users').
doc_moved(le_lps_surface, 'user/reference/le-for-lps').

docs_raw(Request) :-
	memberchk(path(Path), Request),
	atom_concat('/docs-raw/', Name0, Path),
	safe_name(Name0, Name),
	(   public_doc(Name) -> true ; throw(http_reply(not_found(Path))) ),
	lps_root(Root),
	atomic_list_concat([Root, '/docs/', Name], File),
	(   exists_file(File)
	->  serve_file(File)
	;   throw(http_reply(not_found(Path)))
	).

/*	No traversal: a document name is a relative path under docs/. It is also
	interpolated into a page, so anything that could end a string or open a
	tag is out — the check is cheap and the alternative is an injection in
	the one place a URL reaches HTML. */
safe_name(N, N) :-
	\+ sub_atom(N, _, _, _, '..'),
	\+ sub_atom(N, 0, _, _, '/'),
	forall(sub_atom(N, _, 1, _, C), safe_name_char(C)).

safe_name_char(C) :- char_type(C, alnum), !.
safe_name_char('_'). safe_name_char('-'). safe_name_char('.'). safe_name_char('/').

serve_file(File) :-
	file_mime(File, Mime),
	(   sub_atom(Mime, 0, _, _, 'text/') ; sub_atom(Mime, _, _, _, 'javascript')
	;   sub_atom(Mime, _, _, _, 'json') ; sub_atom(Mime, _, _, _, 'svg')
	),
	!,
	read_file_to_string(File, S0, [encoding(utf8)]),
	(   Mime == 'text/html'
	->  telemetry_page(S0, S)
	;   S = S0
	),
	format('Content-type: ~w; charset=UTF-8~n~n', [Mime]),
	write(S).
serve_file(File) :-
	file_mime(File, Mime),
	read_file_to_codes_bin(File, Codes),
	format('Content-type: ~w~n~n', [Mime]),
	forall(member(C, Codes), put_byte(C)).

read_file_to_codes_bin(File, Codes) :-
	setup_call_cleanup(open(File, read, S, [type(binary)]),
			   read_stream_to_codes(S, Codes),
			   close(S)).

file_mime(File, Mime) :-
	file_name_extension(_, Ext, File),
	( mime_of(Ext, Mime) -> true ; Mime = 'application/octet-stream' ).

mime_of(html, 'text/html').
mime_of(js,   'text/javascript').
mime_of(mjs,  'text/javascript').
mime_of(css,  'text/css').
mime_of(json, 'application/json').
mime_of(svg,  'image/svg+xml').
mime_of(png,  'image/png').
mime_of(jpg,  'image/jpeg').
mime_of(ttf,  'font/ttf').
mime_of(woff, 'font/woff').
mime_of(woff2,'font/woff2').
mime_of(wasm, 'application/wasm').
mime_of(data, 'application/octet-stream').
mime_of(md,   'text/markdown').
mime_of(txt,  'text/plain').

ide_dist_file(Rel, File) :-
	\+ sub_atom(Rel, _, _, _, '..'),
	lps_root(Root),
	atomic_list_concat([Root, '/src/ide/dist/', Rel], File),
	exists_file(File).


%!	lps_server(+Port) is det.
lps_server(Port) :- lps_server(Port, []).

lps_server(Port, Options) :-
	(   memberchk(token(T), Options)
	->  retractall(auth_token(_)), assertz(auth_token(T))
	;   true
	),
	%  Ask each provider with a key what models it has, in the background: a
	%  provider being slow must not make `./lps ide` slow to come up.
	catch(models_start, _, true),
	%  Signing in, and the licence checks that go with it (lps_plus.pl).
	lps_plus_accounts,
	http_server(http_dispatch, [port(Port)]).

lps_stop(Port) :- http_stop_server(Port, []).

/* Cross-origin, deliberately. The editor that drives this endpoint is served
   by LE2 on another port (docs/project/plans/le_lps_design.md §3: two backends, no proxy), so
   every request from it is cross-origin and a browser will not send one without
   these headers. LPS_ORIGIN pins the allowed origin for a deployment; with none
   set it is `*`, which is right for a laptop and wrong for a public server —
   which is why LPS_TOKEN exists and why docs/dev/deploy.md says to set it.
*/
lpsapi(Request) :-
	memberchk(method(options), Request), !,
	cors_headers,
	format('Content-type: text/plain~n~n').
lpsapi(Request) :-
	http_read_json_dict(Request, Dict),
	(   authorised(Dict)
	->  (   catch(handle(Dict, Reply), E, ( report_api(Dict, E), error_reply(E, Reply) ))
	    ->  true
	    ;   report_api(Dict, failed), fail
	    )
	;   Reply = _{ok: false, error: "unauthorised"}
	),
	cors_headers,
	reply_json_dict(Reply).

/*  `POST /mcp` — the Model Context Protocol surface (src/edges/lps_mcp.pl).

    An MCP client has nowhere to put an operation's `token` field: its body is
    a JSON-RPC message whose shape the protocol fixes. So a server that wants
    a token takes it where an HTTP client can put one — `Authorization: Bearer
    <token>`, or `?token=` on the URL, which is what the `mcp-remote` bridge
    can pass. A server with no token configured (local development) answers
    anyone, exactly as /lpsapi does.
*/
mcp_endpoint(Request) :-
	memberchk(method(options), Request), !,
	cors_headers,
	format('Content-type: text/plain~n~n').
mcp_endpoint(Request) :-
	(   mcp_authorised(Request)
	->  cors_headers,
	    mcp_http(Request)
	;   cors_headers,
	    reply_json_dict(_{jsonrpc: "2.0", id: null,
			      error: _{code: -32001, message: "unauthorised"}},
			    [status(401)])
	).

mcp_authorised(Request) :-
	(   auth_token(T)
	->  mcp_given_token(Request, Given), same_token(Given, T)
	;   true
	).

mcp_given_token(Request, Token) :-
	(   memberchk(authorization(Auth), Request),
	    text_to_string(Auth, S),
	    string_concat("Bearer ", Token0, S)
	->  Token = Token0
	;   memberchk(search(Search), Request),
	    memberchk(token=Token, Search)
	).

%	To Sentry, when the server is configured for it (lps_telemetry.pl): the
%	operation's name and the error, nothing else of the request.
report_api(_, Error) :-
	stale_handle(Error, _), !.        % expected, and explained: error_reply/2
report_api(Dict, Error) :-
	( get_dict(operation, Dict, Op) -> true ; Op = none ),
	telemetry_report(Error, [operation(Op)]).

/*  Whether this server wants a token, asked *before* the first request that
    would be refused for want of one.

    Without this the IDE's only way to find out is to fail: a deployment with
    `LPS_TOKEN` set answers "unauthorised" to every operation, so the editor
    opens on an empty buffer, the example browser sits on "loading…" and
    nothing on screen says why. A page has to be able to ask.

    It is deliberately unauthenticated and deliberately says nothing else. That
    a server requires a token is not a secret — it is the first thing a refused
    client learns anyway — and the reply carries no program, no session and no
    configuration. */
api_status(Request) :-
	memberchk(method(options), Request), !,
	cors_headers,
	format('Content-type: text/plain~n~n').
api_status(_Request) :-
	( auth_token(_) -> Needs = true ; Needs = (false) ),
	lps_le_available(How),
	( How == none -> Le = (false) ; Le = true ),
	cors_headers,
	reply_json_dict(_{ok: true, token_required: Needs, logical_english: Le}).

cors_headers :-
	( getenv('LPS_ORIGIN', O), O \== '' -> Origin = O ; Origin = '*' ),
	format('Access-Control-Allow-Origin: ~w~n', [Origin]),
	format('Access-Control-Allow-Methods: POST, OPTIONS~n', []),
	format('Access-Control-Allow-Headers: Content-Type~n', []),
	format('Access-Control-Max-Age: 86400~n', []).

/*  The token, compared as *text*.

    `get_dict(token, Dict, T)` unified the configured token with the one in the
    request, and those are never the same term: `LPS_TOKEN` arrives from
    `getenv/2` as an atom and JSON gives a string, so an atom was being unified
    with a string and a tokened server refused **every** request — including
    the ones carrying the right token. It fails closed, so nothing was ever
    admitted that should not have been; what it did instead was make every
    tokened deployment unusable, which is how it was found.

    Nothing here exercised it: the harness, the browser tests and every local
    `./lps ide` run without a token, which is the branch below. */
authorised(Dict) :-
	(   auth_token(T)
	->  get_dict(token, Dict, Given),
	    same_token(Given, T)
	;   true                       % no token configured: local development
	).

same_token(A, B) :-
	catch(( text_to_string(A, S1), text_to_string(B, S2), S1 == S2 ), _, fail).

/*  A handle that names something this process no longer holds is not a fault
    of the server and not a mistake of the client.

    Sessions, programs and live runs live in one process's memory, and the
    deployment stops its machine when nobody is asking (fly.toml:
    `auto_stop_machines`, `min_machines_running = 0`). A page left open over
    lunch therefore holds ids of a process that no longer exists, and the next
    click — Timeline, 2D, anything — arrived as `lps_no_such_session('s1-…')`:
    reported to Sentry as an unknown error term, and shown to the reader as
    that same term, about something they did nothing to cause.

    So it is answered in words, with `stale: true` for the IDE to act on (it
    re-runs the buffer, which is all it takes: ui/src/main.js, refreshPane),
    and it is not reported. A real fault still is.
*/
stale_handle(error(lps_no_such_session(_), _), "run").
stale_handle(error(lps_no_such_program(_), _), "program").

error_reply(E, _{ok: false, error: Msg, stale: true}) :-
	stale_handle(E, What), !,
	format(string(Msg),
	       "this ~w is gone: the server was restarted since it was made \c
		(it stops when idle). Press Run to make a new one.", [What]).
error_reply(E, _{ok: false, error: Msg}) :-
	message_to_codes_(E, Msg).

message_to_codes_(E, S) :- format(string(S), '~q', [E]).

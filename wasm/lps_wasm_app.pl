/* lps_wasm_app.pl — LPS2 in the browser, as the whole application.
 *
 * There has been an LPS2 in a browser since M11: `src/edges/lps_wasm.pl`
 * writes a page carrying one program and the engine, which runs it and prints
 * the trace. That was the proof. This is the deployment: the *IDE* — the
 * editor, the timeline, the 2D scene, the explanations, the examples — with
 * the engine compiled into the page under it and no server anywhere.
 *
 * What makes it possible is that the IDE already speaks to one endpoint.
 * Every operation is a JSON object POSTed to /lpsapi, which is why
 * `lps_api.pl` could be lifted out of `lps_http.pl` without changing an
 * operation: the server calls handle/2 after reading a POST, and this file
 * calls the same handle/2 after reading a message from the page. One
 * implementation, two transports.
 *
 * What the browser costs, plainly:
 *
 *   * one thread. A run is synchronous here as it is in the engine, but the
 *     assistant's jobs and live sessions, which are threads on the server,
 *     are not available;
 *   * no sub-processes, so the LE2-as-a-subprocess transport is out; the
 *     in-process one (vendored into the payload) is the one that works;
 *   * no sockets: an outbound request goes through the page, and a browser
 *     will not let a page reach another origin uninvited — which is what the
 *     deployment's own proxy is for (wasm/api/proxy.js);
 *   * time limits measured in inferences rather than seconds
 *     (wasm/shims/time.pl).
 *
 * Everything else is the engine as it is: the same cycle, the same planner,
 * the same explanations, the same conformance behaviour.
 */

:- module(lps_wasm_app, [
	lps_wasm_init/1,         % +ConfigDict
	lps_wasm_call/2,         % +RequestJSONString, -ReplyJSONString
	lps_wasm_fetch/2,        % +RequestDict, -ReplyDict
	lps_wasm_version/1       % -Atom
	]).

/*  The shims, before anything that needs them: a directive runs when it is
    read, so this is in force by the time the use_module/1 below reads
    lps_api.pl and, through it, every edge. Appended rather than prepended —
    a real library always wins, and the shims are only ever reached for the
    ones that are not in the image at all. See wasm/shims/README.md.  */
:- multifile user:file_search_path/2.
:- prolog_load_context(directory, WasmDir),
   atom_concat(WasmDir, '/shims', ShimDir),
   ( user:file_search_path(library, ShimDir) -> true
   ; assertz(user:file_search_path(library, ShimDir)) ).

:- use_module(library(json)).
:- use_module(library(lists)).
:- use_module(library(time)).

/*  library(wasm) is how Prolog calls the page: `X := f(Y)`. It is in the
    WebAssembly image and nowhere else, and this file is also read by a plain
    swipl (to check that it still compiles), so its absence has to be
    survivable: without it the calls below throw, and every one of them is
    inside a catch/3 that expects exactly that.  */
:- if(exists_source(library(wasm))).
:- use_module(library(wasm)).
:- endif.

:- use_module('../src/edges/lps_api').
:- use_module('../src/edges/lps_le').

:- dynamic external_proxy/1.
:- dynamic wasm_build_info/1.

lps_wasm_version(Info) :-
	( wasm_build_info(Info) -> true ; Info = 'unknown build' ).

		 /*******************************
		 *	     STARTING		*
		 *******************************/

%!	lps_wasm_init(+Config) is det.
%
%	Called once by the worker, after it has unpacked the payload into the
%	virtual file system. Every key of Config is optional:
%
%	  - `build`    what the IDE's status line should say
%	  - `proxy`    where to send a request this page may not make itself;
%	               without one, an outbound fetch fails as a blocked
%	               cross-origin fetch does
%	  - `le`       `true` if the payload carries a vendored Logical English
%	               at /app/vendor/le2 (wasm/build.sh --with-le)
%	  - `inferencesPerSecond`  what a second is worth here (wasm/shims/time.pl)
lps_wasm_init(Config) :-
	( get_dict(build, Config, B) -> retractall(wasm_build_info(_)), assertz(wasm_build_info(B)) ; true ),
	( get_dict(proxy, Config, P), P \== null, P \== ""
	->  retractall(external_proxy(_)), assertz(external_proxy(P)) ; true ),
	( get_dict(inferencesPerSecond, Config, IPS), integer(IPS), IPS > 0
	->  set_prolog_flag(lps_wasm_inferences_per_second, IPS) ; true ),
	/*  Logical English, when the build carried one. This is the in-process
	    transport of docs/dev/le-lps-interface.md §3.5 — the only one a browser
	    has: LPS_LE2_URL would be a cross-origin POST that no LE2 server
	    invites, and LPS_LE2_DIR needs a process to start.  */
	(   get_dict(le, Config, true), exists_file('/app/vendor/le2/le_service.pl')
	->  setenv('LPS_LE2_LIB', '/app/vendor/le2')
	;   true
	).
	/*  Nothing reports home from here, and nothing has to be turned off to
	    keep it that way: lps_telemetry.pl is configured entirely from the
	    environment (LPS_SENTRY_DSN and friends), and the only environment
	    variable this Prolog has is the one set just above.  */

		 /*******************************
		 *	    THE ONE CALL	*
		 *******************************/

%!	lps_wasm_call(+RequestJSON:string, -ReplyJSON:string) is det.
%
%	One operation, in and out as JSON text — text rather than a dict across
%	the bridge on purpose: the request comes from `JSON.stringify` in the
%	page and the reply goes to `JSON.parse`, so the IDE's own fetch hook can
%	hand it to code that cannot tell it from a server's.
%
%	There is no token here. A token protects a *shared* server from being
%	used by whoever finds it; this Prolog belongs to the tab it is running
%	in, and there is nobody else to keep out.
lps_wasm_call(RequestJSON, ReplyJSON) :-
	(   catch(atom_json_dict(RequestJSON, Dict, []), E0,
		  ( error_text(E0, M0), Reply = _{ok: false, error: M0} ))
	->  ( var(Reply) -> call_operation(Dict, Reply) ; true )
	;   Reply = _{ok: false, error: "the request was not JSON"}
	),
	with_output_to(string(ReplyJSON), json_write_dict(current_output, Reply, [width(0)])).

call_operation(Dict, Reply) :-
	operation_limit(Dict, Limit),
	(   catch(call_with_time_limit(Limit, lps_api:handle(Dict, Reply0)), E, Caught = E)
	->  ( var(Caught) -> Reply = Reply0 ; failure_reply(Caught, Reply) )
	;   failure_reply(failed, Reply)
	).

%	lps_http.pl gives an operation 300 seconds. Here the limit is counted in
%	inferences (wasm/shims/time.pl) and the number is the same one, so that a
%	program that is too slow is too slow in both deployments.
operation_limit(_Dict, 300).

failure_reply(time_limit_exceeded, _{ok: false, error: Msg}) :- !,
	Msg = "this ran out of time in the browser. The WebAssembly build \c
	       measures a time limit in inferences rather than seconds; a long \c
	       run may need a larger budget.".
failure_reply(Error, _{ok: false, error: Msg}) :-
	error_text(Error, Msg).

error_text(failed, "the operation failed") :- !.
error_text(error(existence_error(procedure, PI), _), Msg) :- !,
	format(atom(A), "no such predicate: ~w (a part of LPS2 the WebAssembly \c
			 build does not carry?)", [PI]), atom_string(A, Msg).
error_text(E, Msg) :- format(string(Msg), '~q', [E]).

		 /*******************************
		 *	    THE OUTSIDE		*
		 *******************************/

%!	lps_wasm_fetch(+Request, -Reply) is det.
%
%	The one way out of this Prolog, used by wasm/shims/http/http_open.pl.
%	Request is `_{url, method, headers, body, timeout}`; Reply is
%	`_{status, headers, body, error}`.
%
%	A request to another origin is sent to the configured proxy instead, as
%	a POST whose body is the request itself. Not for politeness: a browser
%	will not let this page reach an LLM provider at all, and a key that
%	would make the request worth sending has no business being in a page.
lps_wasm_fetch(Request, Reply) :-
	(   external(Request.url), external_proxy(Proxy)
	->  with_output_to(string(Body), json_write_dict(current_output, Request, [width(0)])),
	    Out = _{action: "fetch", url: Proxy, method: "POST",
		    headers: [["Content-Type", "application/json"]],
		    body: Body, timeout: Request.timeout}
	;   Out = Request.put(action, "fetch")
	),
	with_output_to(string(JSON), json_write_dict(current_output, Out, [width(0)])),
	catch(ReplyJSON := lps_wasm_host(JSON), E,
	      throw(error(resource_error(no_host), context(lps_wasm_fetch/2, E)))),
	atom_json_dict(ReplyJSON, Reply, []).

external(URL) :-
	( sub_string(URL, 0, _, _, "http://") ; sub_string(URL, 0, _, _, "https://") ),
	\+ same_origin(URL).

same_origin(URL) :-
	catch(Origin := lps_wasm_host_origin(), _, fail),
	string(Origin), Origin \== "",
	sub_string(URL, 0, _, _, Origin).

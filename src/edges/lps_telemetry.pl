/* lps_telemetry.pl — error reports (Sentry) and web analytics (Cloudflare).

   Both are off unless the server's environment configures them, which only
   the deployed server's does (fly secrets). Then the server reports the
   exceptions of /lpsapi to Sentry, and every page it serves loads
   /telemetry.js (lps_telemetry.js behind the configuration built here),
   which reports the page's own errors, offers Sentry's feedback form, and
   loads Cloudflare's Web Analytics beacon. docs/telemetry.md says how to
   set them up.

       LPS_SENTRY_DSN                  the Sentry project's DSN
       LPS_SENTRY_ENVIRONMENT          default `production`
       LPS_SENTRY_RELEASE              default `lps2@<build stamp>` (src/ide/dist/BUILD.txt)
       LPS_CLOUDFLARE_ANALYTICS_TOKEN  the Cloudflare Web Analytics site's token

   A report carries the operation's name and the error — never a program or
   any other field of the request. It is sent by a thread of its own with a
   five-second timeout, the same error at most once in ten minutes and at
   most sixty reports an hour, so an unreachable Sentry never slows or fails
   a request.

   This is an edge, and LE2's `le_telemetry.pl` is its twin: the same
   design, its own variables (`LE_…`), so that with Logical English loaded in
   this process the two servers still report into their own projects.
*/

:- module(lps_telemetry, [
	telemetry_report/2,	% +Error, +Context
	telemetry_js/1,		% -JavaScript (GET /telemetry.js)
	telemetry_test/1,	% -Reply dict (GET /telemetry_test)
	telemetry_status/1,	% -Dict: which services are configured
	telemetry_page/2,	% +Html0, -Html: the script tag put in a page's head
	sentry_dsn/2,		% +DSN, -dsn(Scheme, Key, Host, Prefix, Project)
	sentry_envelope/4	% +DSN, +Error, +Context, -envelope(Url, Auth, Body)
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(readutil)).
:- use_module(library(uuid)).
:- use_module(library(debug)).
:- use_module(library(http/http_open)).
:- use_module(library(http/json)).

:- dynamic sent/2.		% Key, Time: what was reported, and when
:- dynamic hour/2.		% Start, Count: reports in the current hour

server_name(lps2).
env_prefix('LPS_').

%	The Sentry browser bundle with the feedback form, pinned: a new version
%	is a deliberate change, with its integrity hash
%	(`openssl dgst -sha384 -binary bundle.feedback.min.js | base64`).
sentry_bundle('https://browser.sentry-cdn.com/10.74.0/bundle.feedback.min.js',
	      'sha384-GUfENdldn3DoGJLIx0qBfM3P6kMCt8YiyD3HXEJu5Y8ipyXynEM5+0xXunZ60nF6').

%	Cloudflare Web Analytics' beacon (the snippet of the site's dashboard).
cloudflare_beacon('https://static.cloudflareinsights.com/beacon.min.js').

%	The query parameters of a page's address that Sentry's reports keep: the
%	others can carry a program.
url_params([example]).

%	The feedback form's words. The IDE speaks English only.
feedback_labels(_{ trigger: "Feedback",
		   title: "Report a problem or send feedback",
		   message: "Description",
		   placeholder: "What happened? What did you expect?",
		   name: "Name", email: "Email",
		   submit: "Send", cancel: "Cancel",
		   thanks: "Thank you for your feedback!",
		   required: "(required)" }).

		 /*******************************
		 *	   configuration	*
		 *******************************/

setting(Name, Value) :-
	env_prefix(P),
	atom_concat(P, Name, Var),
	getenv(Var, V0),
	normalize_space(atom(Value), V0),
	Value \== ''.

sentry_config(DSN) :-
	setting('SENTRY_DSN', DSN),
	sentry_dsn(DSN, _).

environment(Env) :-
	( setting('SENTRY_ENVIRONMENT', Env) -> true ; Env = production ).

%	The release: given, or the IDE's build stamp.
release(Release) :-
	(   setting('SENTRY_RELEASE', R0)
	->  true
	;   module_property(lps_telemetry, file(F)),
	    file_directory_name(F, Edges),
	    atomic_list_concat([Edges, '/../ide/dist/BUILD.txt'], Stamp),
	    exists_file(Stamp),
	    read_file_to_string(Stamp, S0, []),
	    normalize_space(atom(S), S0),
	    S \== '',
	    server_name(N),
	    format(atom(R0), '~w@~w', [N, S])
	),
	sanitize_release(R0, Release).

%	Sentry refuses a release with a slash, a backslash or white space.
sanitize_release(R0, R) :-
	atom_codes(R0, Cs0),
	maplist(release_code, Cs0, Cs),
	atom_codes(R, Cs).

release_code(C0, C) :-
	( memberchk(C0, `/\\\t\n\r `) -> C = 0'- ; C = C0 ).

%!	telemetry_status(-Status:dict) is det.
telemetry_status(_{sentry: S, web_analytics: W}) :-
	( sentry_config(_) -> S = true ; S = false ),
	( setting('CLOUDFLARE_ANALYTICS_TOKEN', _) -> W = true ; W = false ).

		 /*******************************
		 *	  the pages' script	*
		 *******************************/

%!	telemetry_page(+Html0, -Html) is det.
%
%	A page with `<script src="/telemetry.js">` first in its head — every
%	page, configured or not: unconfigured, the script is one line that loads
%	nothing.
telemetry_page(Html0, Html) :-
	(   sub_atom(Html0, B, L, A, '<head>')
	->  E is B + L,
	    sub_atom(Html0, 0, E, _, Pre), sub_atom(Html0, _, A, 0, Post),
	    atomic_list_concat([Pre, '\n<script src="/telemetry.js"></script>', Post], Html)
	;   Html = Html0
	).

%!	telemetry_js(-JS:string) is det.
telemetry_js(JS) :-
	(   telemetry_config(Config)
	->  with_output_to(string(CJ), json_write_dict(current_output, Config, [width(0)])),
	    client_script(Client),
	    format(string(JS), "var TELEMETRY = ~w;~n~w", [CJ, Client])
	;   JS = "/* telemetry: off (docs/telemetry.md) */\n"
	).

client_script(Text) :-
	module_property(lps_telemetry, file(F)),
	file_directory_name(F, Dir),
	atomic_list_concat([Dir, '/lps_telemetry.js'], File),
	read_file_to_string(File, Text, [encoding(utf8)]).

telemetry_config(Config) :-
	( sentry_config(DSN) -> sentry_client(DSN, S) ; S = null ),
	( cloudflare_client(W) -> true ; W = null ),
	( S \== null ; W \== null ), !,
	server_name(Server),
	url_params(Keep),
	Config = _{server: Server, sentry: S, webAnalytics: W, urlParams: Keep}.

sentry_client(DSN, Client) :-
	sentry_bundle(Bundle, Integrity),
	environment(Env),
	( release(Rel) -> true ; Rel = null ),
	feedback_labels(Labels),
	Client = _{dsn: DSN, environment: Env, release: Rel,
		   bundle: Bundle, integrity: Integrity, labels: Labels}.

cloudflare_client(_{beacon: Beacon, token: Token}) :-
	setting('CLOUDFLARE_ANALYTICS_TOKEN', Token),
	cloudflare_beacon(Beacon).

		 /*******************************
		 *	   server reports	*
		 *******************************/

%!	telemetry_report(+Error, +Context:list) is det.
%
%	Report Error — an exception term, `failed`, or `message(Text)` — to
%	Sentry, if configured. Context: operation(Op). Never fails, never
%	throws, never waits for Sentry.
telemetry_report(Error, Context) :-
	catch(report_(Error, Context), _, true), !.
telemetry_report(_, _).

report_(Error, Context) :-
	sentry_config(DSN),
	environment(Env),
	( release(Rel) -> Ctx1 = [release(Rel)] ; Ctx1 = [] ),
	append([[environment(Env)], Ctx1, Context], Ctx),
	sentry_envelope(DSN, Error, Ctx, Envelope),
	report_key(Error, Context, Key),
	admit(Key),
	thread_create(post_envelope(Envelope), _, [detached(true)]).

report_key(Error, Context, Key) :-
	error_type_value(Error, Type, Value, _, _),
	( memberchk(operation(Op), Context) -> true ; Op = none ),
	sub_string_prefix(Value, 200, V),
	term_hash(k(Type, V, Op), Key).

%	The same error once in ten minutes; sixty reports an hour in all.
admit(Key) :-
	with_mutex(lps_telemetry, admit_(Key)).

admit_(Key) :-
	get_time(Now),
	\+ ( sent(Key, T), Now - T < 600 ),
	(   hour(Start, Count), Now - Start < 3600
	->  Count < 60, retract(hour(Start, Count)), C1 is Count + 1,
	    assertz(hour(Start, C1))
	;   retractall(hour(_, _)), assertz(hour(Now, 1))
	),
	retractall(sent(Key, _)),
	assertz(sent(Key, Now)),
	Old is Now - 600,
	forall(( sent(K, T), T < Old ), retractall(sent(K, T))).

post_envelope(envelope(Url, Auth, Body)) :-
	catch(( setup_call_cleanup(
		    http_open(Url, In,
			      [ method(post),
				post(string('application/x-sentry-envelope', Body)),
				request_header('X-Sentry-Auth'=Auth),
				timeout(5), status_code(Code) ]),
		    read_string(In, _, _),
		    close(In)),
		debug(telemetry, 'Sentry answered ~w', [Code]) ),
	      E,
	      debug(telemetry, 'Sentry unreachable: ~q', [E])).

%!	sentry_dsn(+DSN, -Parts) is semidet.
%
%	A DSN `https://<key>@<host>[/<path>]/<project>` as
%	dsn(Scheme, Key, Host, Prefix, Project), Prefix '' or '/<path>'.
sentry_dsn(DSN, dsn(Scheme, Key, Host, Prefix, Project)) :-
	atom_string(DSN, S),
	sub_string(S, B, 3, _, "://"), !,
	sub_string(S, 0, B, _, Scheme0),
	memberchk(Scheme0, ["https", "http"]),
	A is B + 3,
	sub_string(S, A, _, 0, Rest),
	sub_string(Rest, At, 1, _, "@"), !,
	sub_string(Rest, 0, At, _, KeyPart),
	split_string(KeyPart, ":", "", [Key0|_]),
	Key0 \== "",
	A1 is At + 1,
	sub_string(Rest, A1, _, 0, HostPath),
	split_string(HostPath, "/", "", [Host0|Segs0]),
	Host0 \== "",
	exclude(==(""), Segs0, Segs),
	append(PrefixSegs, [Project0], Segs),
	number_string(_, Project0),
	(   PrefixSegs == []
	->  Prefix = ''
	;   atomic_list_concat([''|PrefixSegs], '/', Prefix)
	),
	maplist(atom_string, [Scheme, Key, Host, Project], [Scheme0, Key0, Host0, Project0]).

%!	sentry_envelope(+DSN, +Error, +Context, -Envelope) is semidet.
%
%	Envelope = envelope(Url, AuthHeader, Body): one event in Sentry's
%	envelope format. Context: operation(Op), environment(E), release(R).
sentry_envelope(DSN, Error, Context, envelope(Url, Auth, Body)) :-
	sentry_dsn(DSN, dsn(Scheme, Key, Host, Prefix, Project)),
	format(atom(Url), '~w://~w~w/api/~w/envelope/', [Scheme, Host, Prefix, Project]),
	server_name(Server),
	format(atom(Auth), 'Sentry sentry_version=7, sentry_key=~w, sentry_client=~w-prolog/1.0',
	       [Key, Server]),
	sentry_event(Error, Context, Event),
	get_time(Now),
	format_time(atom(SentAt), '%FT%T%:z', Now),
	atom_string(DSN, DSNs),
	Header = _{event_id: Event.event_id, sent_at: SentAt, dsn: DSNs},
	ItemHeader = _{type: event, content_type: 'application/json'},
	maplist(json_line, [Header, ItemHeader, Event], Lines),
	atomic_list_concat(Lines, '\n', Body0),
	string_concat(Body0, "\n", Body).

json_line(Dict, Line) :-
	with_output_to(string(Line), json_write_dict(current_output, Dict, [width(0)])).

sentry_event(Error, Context, Event) :-
	uuid(U, [version(4)]),
	split_string(U, "-", "", Parts),
	atomic_list_concat(Parts, Id0),
	downcase_atom(Id0, Id),
	get_time(Now),
	server_name(Server),
	error_type_value(Error, Type, Value, Level, Extra),
	( memberchk(operation(Op0), Context) -> to_text(Op0, Op) ; Op = "none" ),
	Event0 = _{event_id: Id, timestamp: Now, platform: other, level: Level,
		   logger: Server, server_name: Server,
		   tags: _{operation: Op, server: Server},
		   sdk: _{name: 'lps2.prolog', version: '1.0.0'},
		   extra: Extra},
	(   Error = message(_)
	->  Event1 = Event0.put(message, _{formatted: Value})
	;   Event1 = Event0.put(exception,
			 _{values: [_{type: Type, value: Value,
				      mechanism: _{type: generic, handled: true}}]})
	),
	foldl(context_field, Context, Event1, Event).

context_field(environment(E), D0, D) :- !, to_text(E, T), D = D0.put(environment, T).
context_field(release(R), D0, D) :- !, to_text(R, T), D = D0.put(release, T).
context_field(_, D, D).

%	What kind of error, and its message (no backtrace: that goes to Extra).
error_type_value(message(M), message, Value, info, _{}) :- !,
	to_text(M, Value0), sub_string_prefix(Value0, 1000, Value).
error_type_value(failed, failure, "the operation failed without an exception", error, _{}) :- !.
error_type_value(error(Formal, Ctx), Type, Value, error, Extra) :- !,
	(   var(Formal) -> Type = error
	;   compound(Formal) -> functor(Formal, Type, _)
	;   atomic(Formal) -> Type = Formal
	;   Type = error
	),
	(   nonvar(Ctx), Ctx = context(Stack, Msg), nonvar(Stack), Stack = prolog_stack(Frames)
	->  message_text(error(Formal, context(_, Msg)), Value0),
	    backtrace_text(Frames, BT),
	    Extra = _{backtrace: BT}
	;   message_text(error(Formal, Ctx), Value0),
	    Extra = _{}
	),
	sub_string_prefix(Value0, 1000, Value).
error_type_value(Thrown, throw, Value, error, _{}) :-
	format(string(Value0), '~W', [Thrown, [max_depth(6), quoted(true), portray(false)]]),
	sub_string_prefix(Value0, 1000, Value).

message_text(E, S) :-
	catch(( '$messages':translate_message(E, Lines, []),
		with_output_to(string(S0), print_message_lines(current_output, '', Lines)),
		normalize_space(string(S), S0) ), _, fail), !.
message_text(E, S) :-
	format(string(S), '~W', [E, [max_depth(6), quoted(true)]]).

backtrace_text(Frames, Text) :-
	catch(( use_module(library(prolog_stack)),
		with_output_to(string(T0), prolog_stack:print_prolog_backtrace(current_output, Frames)),
		sub_string_prefix(T0, 4000, Text) ), _, Text = "").

sub_string_prefix(S0, Max, S) :-
	to_text(S0, S1),
	(   string_length(S1, L), L > Max
	->  sub_string(S1, 0, Max, _, S)
	;   S = S1
	).

to_text(X, S) :- ( string(X) -> S = X ; atomic(X) -> atom_string(X, S) ; format(string(S), '~w', [X]) ).

		 /*******************************
		 *	      testing		*
		 *******************************/

%!	telemetry_test(-Reply:dict) is det.
%
%	What GET /telemetry_test does: a test report through the path real
%	exceptions take, and which services are on. Throttled like any report
%	(once in ten minutes), so the URL cannot be used to flood the project.
telemetry_test(Reply) :-
	telemetry_status(Status),
	(   Status.sentry == true
	->  E = error(telemetry_test, context(telemetry_test/0, 'a test report, sent from /telemetry_test')),
	    report_key(E, [operation(telemetry_test)], Key),
	    (   \+ ( sent(Key, T), get_time(Now), Now - T < 600 )
	    ->  telemetry_report(E, [operation(telemetry_test)]), Sent = sent
	    ;   Sent = 'already sent in the last ten minutes'
	    )
	;   Sent = 'not configured'
	),
	Reply = Status.put(_{server: lps2, sentry_test: Sent}).

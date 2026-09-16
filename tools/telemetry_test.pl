/* telemetry_test.pl — error reports and analytics (src/edges/lps_telemetry.pl).

	./myswipl.sh -q -g "consult('tools/telemetry_test.pl')" -g "tel:main" -t halt

   Off unless configured: no variable, no script beyond a no-op, no report.
   Configured: the DSN read right, the envelope Sentry expects — checked by a
   mock Sentry on a local port, which receives what the server sends — the
   same error sent once, the pages carrying the script, and nothing of the
   request but its operation.
*/

:- module(tel, [main/0]).

:- use_module('../src/edges/lps_telemetry').
:- use_module(library(http/thread_httpd)).
:- use_module(library(http/http_client)).
:- use_module(library(http/json)).
:- use_module(library(lists)).

:- dynamic failures/1.
:- dynamic received/2.		% Auth, Body

main :-
	retractall(failures(_)), assertz(failures(0)),
	clear,
	forall(clause(check(What), _), run_case(What)),
	clear,
	failures(N),
	(   N =:= 0
	->  format('~n=== telemetry: every case behaves ===~n', [])
	;   format('~n=== telemetry: ~w FAILED ===~n', [N]), halt(1)
	).

run_case(What) :-
	(   catch(check(What), E, ( print_message(error, E), fail ))
	->  format('  ok    ~w~n', [What])
	;   format('  FAIL  ~w~n', [What]),
	    retract(failures(N)), N1 is N + 1, assertz(failures(N1))
	).

clear :-
	forall(member(V, ['LPS_SENTRY_DSN', 'LPS_SENTRY_ENVIRONMENT', 'LPS_SENTRY_RELEASE',
			  'LPS_CLOUDFLARE_ANALYTICS_TOKEN']),
	       unsetenv(V)),
	retractall(lps_telemetry:sent(_, _)),
	retractall(lps_telemetry:hour(_, _)).

check('a DSN is read into its parts') :-
	sentry_dsn('https://abc@o42.ingest.de.sentry.io/4507', D1),
	D1 == dsn(https, abc, 'o42.ingest.de.sentry.io', '', '4507'),
	sentry_dsn("http://k:s@localhost:9000/sentry/12", D2),
	D2 == dsn(http, k, 'localhost:9000', '/sentry', '12').
check('a text that is not a DSN is refused') :-
	\+ sentry_dsn('not a dsn', _).
check('unconfigured: the script loads nothing, a report sends nothing') :-
	telemetry_status(S), S.sentry == false, S.web_analytics == false,
	telemetry_js(JS), \+ sub_string(JS, _, _, _, "sentry-cdn"),
	\+ sub_string(JS, _, _, _, "cloudflareinsights"),
	telemetry_report(error(foo, _), [operation(run)]),
	\+ lps_telemetry:sent(_, _).
check('every page gets the script in its head') :-
	telemetry_page('<html><head><title>t</title></head></html>', H),
	sub_atom(H, B1, _, _, '<script src="/telemetry.js"></script>'),
	sub_atom(H, B2, _, _, '<title>'), B1 < B2.
check('the envelope is the one Sentry reads') :-
	sentry_envelope('https://pub@o1.ingest.sentry.io/77',
		      error(existence_error(procedure, foo/0), foo/0),
		      [operation(run), environment(staging)],
		      envelope(Url, Auth, Body)),
	Url == 'https://o1.ingest.sentry.io/api/77/envelope/',
	sub_atom(Auth, _, _, _, 'sentry_key=pub'),
	split_string(Body, "\n", "", [H, I, E, ""]),
	atom_json_dict(H, Header, []), atom_json_dict(I, Item, []), atom_json_dict(E, Event, []),
	Header.event_id == Event.event_id, Item.type == "event",
	Event.tags.operation == "run", Event.tags.server == "lps2",
	Event.environment == "staging",
	[X] = Event.exception.values, X.type == "existence_error".
check('configured: the script carries both services') :-
	setenv('LPS_SENTRY_DSN', 'https://pub@o1.ingest.sentry.io/77'),
	setenv('LPS_CLOUDFLARE_ANALYTICS_TOKEN', '156f86d887d3403980efe3773373da6f'),
	telemetry_js(JS), clear,
	split_string(JS, "\n", "", [Line|_]),
	string_concat("var TELEMETRY = ", J0, Line), string_concat(J, ";", J0),
	atom_json_dict(J, C, []),
	C.sentry.dsn == "https://pub@o1.ingest.sentry.io/77",
	C.webAnalytics.token == "156f86d887d3403980efe3773373da6f",
	C.webAnalytics.beacon == "https://static.cloudflareinsights.com/beacon.min.js",
	sub_string(JS, _, _, _, "data-cf-beacon"),
	\+ sub_string(JS, _, _, _, "posthog").
check('web analytics alone: the beacon, no Sentry') :-
	setenv('LPS_CLOUDFLARE_ANALYTICS_TOKEN', 'tok'),
	telemetry_status(S), telemetry_js(JS), clear,
	S.sentry == false, S.web_analytics == true,
	split_string(JS, "\n", "", [Line|_]),
	string_concat("var TELEMETRY = ", J0, Line), string_concat(J, ";", J0),
	atom_json_dict(J, C, []),
	C.sentry == null, C.webAnalytics.token == "tok".
check('a report reaches Sentry, once') :-
	setup_call_cleanup(
	 ( retractall(received(_, _)), http_server(mock_sentry, [port(localhost:Port)]) ),
	 ( format(atom(DSN), 'http://pubkey@localhost:~w/5', [Port]),
	   setenv('LPS_SENTRY_DSN', DSN),
	   Err = error(type_error(integer, abc), context(foo/1, _)),
	   telemetry_report(Err, [operation(run)]),
	   telemetry_report(Err, [operation(run)]),
	   wait_for(1), sleep(0.5),
	   aggregate_all(count, received(_, _), 1),
	   received(Auth, Body),
	   sub_atom(Auth, _, _, _, 'sentry_key=pubkey'),
	   split_string(Body, "\n", "", [_, _, EJ, ""]),
	   atom_json_dict(EJ, Ev, []), Ev.tags.operation == "run" ),
	 ( http_stop_server(localhost:Port, []), clear )).
check('an unreachable Sentry does not hold the request') :-
	setenv('LPS_SENTRY_DSN', 'http://k@localhost:1/5'),
	get_time(T0), telemetry_report(error(foo, _), [operation(x)]), get_time(T1),
	clear, T1 - T0 < 0.5.

mock_sentry(Request) :-
	memberchk(x_sentry_auth(Auth), Request),
	http_read_data(Request, Body, [to(string)]),
	assertz(received(Auth, Body)),
	format('Content-type: application/json~n~n{"id":"x"}').

wait_for(N) :-
	between(1, 50, _),
	(   aggregate_all(count, received(_, _), N) -> true ; sleep(0.1), fail ), !.

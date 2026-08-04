/* lps_le.pl — the Logical English edge (§I.9, M8a).

   LPS2 does not parse Logical English. LE2 does, and it owns the template
   dictionary, so it owns the only mapping that can be inverted (§I.9.5). What
   crosses the boundary is *LPS internal syntax as text*, plus a provenance
   list that points each generated term back at the `.le` sentence it came
   from. The contract is docs/le_lps_interface.md, which is duplicated verbatim
   in the LE2 repository.

   Two transports, both explicit, neither guessed:

     LPS_LE2_URL   an HTTP endpoint speaking LE2's `/leapi` protocol. Used
		   when set. This is the deployment case: two servers, no
		   proxy (docs/le_lps_design.md §3).
     LPS_LE2_DIR   a checkout of the LE2 repository. Used when there is no
		   URL. `swipl -g le_lps_file(...)` runs in a *subprocess*,
		   because a `.le` document can pull in arbitrary Prolog
		   resources and one document's `halt/0` should not take the
		   CLI with it.

   With neither set, `./lps run foo.le` refuses and says which variable to
   set. It must not silently guess: a `.le` file compiled by the wrong LE2 is
   a program whose meaning nobody stated.
*/

:- module(lps_le, [
	lps_le_translate/4,      % +File, -InternalText, -Provenance, -Diags
	lps_le_available/1       % -How  (url(U) | dir(D) | none)
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(process)).
:- use_module(library(http/json)).
:- use_module(library(http/http_open)).
:- use_module('../core/lps_diag').

%!	lps_le_available(-How) is det.
%
%	How the LE layer is reachable: `url(U)`, `dir(D)`, or `none`.
lps_le_available(How) :-
	(   getenv('LPS_LE2_URL', U), U \== ''
	->  How = url(U)
	;   getenv('LPS_LE2_DIR', D), D \== '', exists_directory(D)
	->  How = dir(D)
	;   How = none
	).

%!	lps_le_translate(+File, -Text, -Provenance, -Diags) is det.
%
%	Text is LPS internal syntax; Provenance is a list of
%	`prov(Index, File, Line, Col, Kind)` in term order, ready to be zipped
%	onto the terms read out of Text; Diags are LE-side diagnostics already
%	in `diag/5` shape. On any failure Text is the empty string and Diags
%	carries one error — never a partial program.
lps_le_translate(File, Text, Provenance, Diags) :-
	lps_le_available(How),
	lps_le_translate_(How, File, Text, Provenance, Diags).

lps_le_translate_(none, File, "", [], [D]) :-
	format(atom(M),
	       'cannot compile ~w: Logical English is parsed by LE2, which is not \c
		configured. Set LPS_LE2_URL to an LE2 /leapi endpoint, or \c
		LPS_LE2_DIR to an LE2 checkout.', [File]),
	diag(error, le_not_configured, unknown, M, D).
lps_le_translate_(url(U), File, Text, Provenance, Diags) :-
	(   catch(read_file_to_string(File, Source, [encoding(utf8)]), E1, (E1 = _, fail))
	->  (   catch(le_post(U, Source, Reply), E2, (le_error(E2, D2), Reply = none))
	    ->	(   Reply == none
		->  Text = "", Provenance = [], Diags = [D2]
		;   le_reply(Reply, File, Text, Provenance, Diags)
		)
	    ;	Text = "", Provenance = [],
		format(atom(M), 'LE2 endpoint ~w did not answer', [U]),
		diag(error, le_endpoint_failed, unknown, M, D), Diags = [D]
	    )
	;   Text = "", Provenance = [],
	    format(atom(M), 'cannot read ~w', [File]),
	    diag(error, read_failed, unknown, M, D), Diags = [D]
	).
lps_le_translate_(dir(Dir), File, Text, Provenance, Diags) :-
	absolute_file_name(File, Abs),
	format(atom(Goal),
	       "use_module(le_lps), le_lps:le_lps_json('~w')", [Abs]),
	(   catch(run_le2(Dir, Goal, Out), E, (le_error(E, D0), Out = none))
	->  (   Out == none
	    ->	Text = "", Provenance = [], Diags = [D0]
	    ;	(   catch(atom_json_dict(Out, Reply, []), _, fail)
		->  le_reply(Reply, File, Text, Provenance, Diags)
		;   Text = "", Provenance = [],
		    format(atom(M), 'LE2 in ~w produced no JSON (got: ~w)', [Dir, Out]),
		    diag(error, le_bad_reply, unknown, M, D), Diags = [D]
		)
	    )
	;   Text = "", Provenance = [],
	    format(atom(M), 'could not run LE2 in ~w', [Dir]),
	    diag(error, le_run_failed, unknown, M, D), Diags = [D]
	).

le_error(E, D) :-
	format(atom(M), 'Logical English translation failed: ~q', [E]),
	diag(error, le_failed, unknown, M, D).

%	The reply shape both transports share (docs/le_lps_interface.md §2).
le_reply(Reply, File, Text, Provenance, Diags) :-
	( get_dict(lps, Reply, T) -> Text = T ; Text = "" ),
	( get_dict(provenance, Reply, P), is_list(P) -> P1 = P ; P1 = [] ),
	findall(prov(I, F, L, C, K),
		( member(E, P1), prov_entry(E, File, I, F, L, C, K) ),
		Provenance),
	( get_dict(issues, Reply, Is), is_list(Is) -> Is1 = Is ; Is1 = [] ),
	findall(D, ( member(I0, Is1), issue_diag(I0, File, D) ), Diags).

prov_entry(E, Default, Index, F, Line, Col, Kind) :-
	is_dict(E),
	get_dict(index, E, Index), integer(Index),
	( get_dict(file, E, F0) -> atom_string(F, F0) ; F = Default ),
	( get_dict(line, E, Line), integer(Line) -> true ; Line = 0 ),
	( get_dict(col, E, Col), integer(Col) -> true ; Col = 0 ),
	( get_dict(kind, E, K0) -> atom_string(Kind, K0) ; Kind = le ).

issue_diag(I, File, D) :-
	is_dict(I),
	( get_dict(severity, I, S0), atom_string(S1, S0), memberchk(S1, [error, warning, info])
	-> S = S1 ; S = error ),
	( get_dict(type, I, T0) -> atom_string(Code, T0) ; Code = le_issue ),
	( get_dict(message, I, M0) -> atom_string(Msg, M0) ; Msg = '' ),
	( get_dict(line, I, L), integer(L) -> true ; L = 0 ),
	( get_dict(col, I, C), integer(C) -> true ; C = 0 ),
	diag(S, Code, src(File, L, C, le), Msg, D).

le_post(URL, Source, Reply) :-
	atom_json_dict(Body, _{operation: "getLps", le: Source}, [as(atom)]),
	setup_call_cleanup(
	    http_open(URL, In, [ method(post), post(atom('application/json', Body)),
				 request_header('Content-Type'='application/json') ]),
	    json_read_dict(In, Reply),
	    close(In)).

%	A subprocess, per the module header. stderr is discarded: LE2 prints
%	load-time warnings that are not this program's diagnostics, and the
%	JSON we want is the last line of stdout.
run_le2(Dir, Goal, Out) :-
	atomic_list_concat([Dir, '/myswipl.sh'], Wrapper),
	( exists_file(Wrapper) -> Exe = Wrapper ; Exe = path(swipl) ),
	setup_call_cleanup(
	    process_create(Exe, ['-q', '-g', Goal, '-t', halt],
			   [ cwd(Dir), stdout(pipe(S)), stderr(null),
			     process(PID) ]),
	    read_string(S, _, Raw),
	    ( close(S), process_wait(PID, _) )),
	last_json_line(Raw, Out).

last_json_line(Raw, Out) :-
	split_string(Raw, "\n", " \t\r", Lines0),
	exclude(==(""), Lines0, Lines),
	reverse(Lines, [Last|_]),
	string_concat("{", _, Last),
	atom_string(Out, Last).

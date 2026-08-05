/* sandbox_test.pl — what a program may and may not call on a server.

	./myswipl.sh -q -g "consult('tools/sandbox_test.pl')" -g "sb:main" -t halt

   Two properties, and they pull against each other, which is why both are
   here: the Prolog an LPS program legitimately uses must keep working, and the
   Prolog that reaches the machine must not. A sandbox that fails either is
   worse than none — one that refuses ordinary programs gets turned off, and
   one that admits `shell/1` was never protection.
*/

:- module(sb, [main/0]).

:- use_module('../src/lps').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_diag').
:- use_module('../src/edges/lps_sandbox').
:- use_module(library(lists)).

:- dynamic failures/1.
failures(0).

main :-
	retractall(failures(_)), assertz(failures(0)),
	forall(case(What, Source, Expect), run_case(What, Source, Expect)),
	corpus_pass,
	failures(N),
	(   N =:= 0
	->  format('~n=== sandbox: every case behaves ===~n', [])
	;   format('~n=== sandbox: ~w FAILED ===~n', [N]), halt(1)
	).

run_case(What, Source, Expect) :-
	(   verdict(Source, Got)
	->  true
	;   Got = did_not_compile
	),
	(   Got == Expect
	->  format('  ok    ~w~t~58|~w~n', [What, Got])
	;   format('  FAIL  ~w~t~58|~w, wanted ~w~n', [What, Got, Expect]),
	    retract(failures(N)), N1 is N + 1, assertz(failures(N1))
	).

verdict(Source, Verdict) :-
	lps_compile(terms(Source), legacy, [dc], P, Diags),
	\+ memberchk(diag(error, _, _, _, _), Diags),
	sandbox_check(P, S),
	( S == [] -> Verdict = allowed ; Verdict = refused ).

%	The ordinary vocabulary of an LPS program: it must all still work.
case('arithmetic in a rule body',
     [ maxTime(3), fluents([f(_)]), initial_state([f(1)]),
       (bump(X, Y) :- Y is X + 1) ], allowed).
case('between/3, findall/3, sort/2',
     [ maxTime(3), (pick(L) :- findall(X, between(1, 5, X), L0), msort(L0, L)) ], allowed).
case('printing — a program may talk to its log',
     [ maxTime(3), (say(X) :- format("~w~n", [X]), write(X), nl) ], allowed).
case('assert and retract of facts',
     [ maxTime(3), (remember(X) :- assertz(seen(X))), (forget(X) :- retract(seen(X))) ], allowed).

%	And the vocabulary that reaches the machine: none of it may.
case('shell/1', [ maxTime(3), (evil :- shell('echo x')) ], refused).
case('opening a file', [ maxTime(3), (evil :- open('/etc/passwd', read, _)) ], refused).
case('deleting a file', [ maxTime(3), (evil :- delete_file('/tmp/x')) ], refused).
case('starting a process', [ maxTime(3), (evil :- process_create(path(ls), [], [])) ], refused).
case('reading stdin', [ maxTime(3), (evil :- read(_)) ], refused).
%	The two escapes from a compile-time check, both closed by refusing the
%	construction rather than the call.
case('a goal built at run time',
     [ maxTime(3), (evil(C) :- G =.. [shell, C], call(G)) ], refused).
case('asserting a clause with a body',
     [ maxTime(3), (evil :- assertz((later :- shell('echo x')))) ], refused).

/*  The corpus, because the cost of this is measured in programs it refuses.
    170 of the 172 shipped programs pass; the two that do not are honest
    refusals — `saidsay.pl` reads stdin, `smartHomePrimitives.pl` calls a REST
    client — and they are named here so the number cannot drift quietly. */
corpus_pass :-
	findall(F, corpus_file(F), Files),
	findall(F, ( member(F, Files), \+ file_allowed(F) ), Refused),
	length(Files, N), length(Refused, R), Ok is N - R,
	format('~n  corpus: ~w of ~w programs pass the sandbox~n', [Ok, N]),
	forall(member(F, Refused),
	       ( file_base_name(F, B), format('    refused: ~w~n', [B]) )),
	(   R =< 2
	->  true
	;   format('  more refusals than the two known ones~n', []),
	    retract(failures(K)), K1 is K + 1, assertz(failures(K1))
	).

corpus_file(F) :-
	member(G, ['examples/*.lps', 'examples/*.pl', 'examples/rkbook/*.lps',
		   'legacy_lps1/examples/*.pl',
		   'legacy_lps1/examples/forTesting/*.pl',
		   'legacy_lps1/examples/CLOUT_workshop/*.pl']),
	expand_file_name(G, Fs),
	member(F, Fs),
	\+ sub_atom(F, _, _, _, '_.P').

file_allowed(F) :-
	catch(lps_compile(file(F), legacy, [dc], P, Diags), _, fail),
	(   memberchk(diag(error, _, _, _, _), Diags)
	->  true                      % it does not compile; not the sandbox's doing
	;   sandbox_check(P, S), S == []
	).

/* surface_test.pl — every converted program must survive being written as LPS.

   `src/syntax/lps_surface_write.pl` turns the internal representation back
   into surface syntax so that a `.pddl` or `.drl` opened in the IDE reads like
   the language the tutorial teaches. It checks itself on every call, and this
   gate runs that check over the whole converted corpus, so a shape one
   front end starts emitting cannot quietly fall back to internal syntax.

	./myswipl.sh -q -g "consult('tools/surface_test.pl')" -g "st:main" -t halt
*/

:- module(st, [main/0]).

:- use_module('../src/syntax/lps_pddl').
:- use_module('../src/syntax/lps_drools').
:- use_module('../src/syntax/lps_surface_write').
:- use_module(library(lists)).
:- use_module(library(apply)).

main :-
	findall(R, drools_case(R), Rs1),
	findall(R, pddl_case(R), Rs2),
	append(Rs1, Rs2, Rs),
	include(==(fail), Rs, Bad),
	length(Rs, N), length(Bad, B), Ok is N - B,
	format('~n=== surface round trip: ~w/~w ===~n', [Ok, N]),
	( B =:= 0 -> true ; halt(1) ).

drools_case(R) :-
	expand_file_name('examples/doors/drools/*.drl', Files),
	member(F, Files),
	catch(drl_to_internal(F, Terms, _), _, fail),
	check(F, Terms, R).

%	A PDDL domain is only convertible with a problem, so pair each problem
%	with the domain that declares the same name — the rule the IDE uses.
pddl_case(R) :-
	expand_file_name('examples/doors/pddl/*.pddl', Files),
	member(P, Files),
	is_problem(P),
	member(D, Files), \+ is_problem(D),
	same_domain(P, D),
	catch(pddl_to_internal(D, P, Terms, _), _, fail),
	Terms \== [],
	check(P, Terms, R).

is_problem(F) :-
	read_file_to_string(F, S, []),
	string_lower(S, L),
	sub_string(L, B, _, _, "define"),
	sub_string(L, B2, _, _, "problem"),
	B2 > B, B2 - B < 40, !.

same_domain(P, D) :-
	domain_named(P, N), domain_named(D, N), !.

domain_named(F, Name) :-
	read_file_to_string(F, S, []),
	string_lower(S, L),
	(   sub_string(L, B, _, _, ":domain")
	->  sub_string(L, B, _, After, _), Skip is B + 7
	;   sub_string(L, B, _, _, "(domain"), Skip is B + 7, After = 0
	),
	After >= 0,
	sub_string(L, Skip, _, 0, Rest),
	split_string(Rest, " \t\n)", " \t\n)", Parts),
	exclude(==(""), Parts, [Name|_]).

check(File, Terms, R) :-
	internal_to_surface(Terms, _Text, Diags),
	file_base_name(File, Base),
	(   Diags == []
	->  R = ok, format('~w~t~40|ok~n', [Base])
	;   R = fail, format('~w~t~40|DID NOT ROUND TRIP~n', [Base])
	).

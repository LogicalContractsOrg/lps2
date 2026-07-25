/* perturb.pl — semantically-neutral-looking perturbations, for bucket
   classification (§I.1.2).

   The point: a `.lpst` records the choice the 2021-era engine happened to make.
   Where several choices were equally eligible, the recorded trace is evidence about
   the engine's *selection strategy*, not about LPS semantics. Perturbing things that
   a declarative reading says should not matter tells us which tests are which:

     none         baseline
     rerun        byte-identical rerun — any divergence means the trace depends on
                  the clock, on hashing, or on machine speed (the engine applies a
                  0.75 s call_with_time_limit per phase)
     rev_clauses  reverse clause order within every predicate group of the internal
                  `_.P` program
     rev_initial  reverse the fluent order inside initial_state/1
     queue_prepend  engine variant: new goals are pushed at the front of the goal
                  queue instead of appended at the end

   The first four are program transforms applied here; queue_prepend is an engine
   transform (see adapter_legacy.pl: engine_variant/2).
*/

:- module(perturb, [
	perturbation/3,          % -Name, -Kind, -Description
	perturb_program/3        % +Name, +InFile, +OutFile
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module('../src/core/lps_ops').   % `_.P` files use `not`, `fluents [...]`, …
%	The table now lives in the engine (§I.4 calls it an interface
%	specification, and both the engine and the harness read the same files);
%	the harness's own copy was deleted rather than kept in step by hand.

perturbation(none,          program, 'baseline: unmodified program and engine').
perturbation(rerun,         program, 'identical rerun (stability probe)').
perturbation(rewrite,       program, 'read and write the program back unchanged (control for rev_*)').
perturbation(rev_clauses,   program, 'reverse clause order within each predicate group').
perturbation(rev_initial,   program, 'reverse the fluent list in initial_state/1').
perturbation(queue_prepend, engine,  'new goals prepended to the goal queue instead of appended').

%!	perturb_program(+Name, +InFile, +OutFile) is det.

perturb_program(Name, In, Out) :-
	memberchk(Name, [none, rerun, queue_prepend]), !,
	copy_file(In, Out).
perturb_program(Name, In, Out) :-
	read_program(In, Terms),
	transform(Name, Terms, Terms1),
	write_program(Out, Terms1).

transform(rewrite, Terms, Terms).
transform(rev_clauses, Terms, Out) :-
	reverse_groups(Terms, Out).
transform(rev_initial, Terms, Out) :-
	maplist(rev_initial_term, Terms, Out).

rev_initial_term(initial_state(L), initial_state(R)) :-
	is_list(L), !, reverse(L, R).
rev_initial_term(T, T).

%	reverse_groups(+Terms, -Terms1): each predicate's clauses keep the same *slots*
%	in the file but appear in reverse order among themselves. Directives and
%	single-clause predicates are untouched.
reverse_groups(Terms, Out) :-
	findall(K-I, (nth0(I, Terms, T), clause_key(T, K)), KIs),
	keysort(KIs, Sorted),
	group_pairs_by_key(Sorted, Groups),
	foldl(reverse_group(Terms), Groups, Terms, Out).

reverse_group(Terms, _Key-Indices, In, Out) :-
	(   Indices = [_,_|_]
	->  maplist([I,C]>>nth0(I, Terms, C), Indices, Clauses),
	    reverse(Clauses, Rev),
	    foldl(set_nth0, Indices, Rev, In, Out)
	;   Out = In
	).

set_nth0(I, C, L0, L) :-
	nth0(I, L0, _, Rest),
	nth0(I, L, C, Rest).

clause_key(T, F/A) :-
	nonvar(T),
	T \= (:- _),
	(   T = (H :- _) -> true ; H = T ),
	nonvar(H),
	functor(H, F, A).

read_program(File, Terms) :-
	setup_call_cleanup(
	    open(File, read, S, [encoding(utf8)]),
	    read_terms(S, Terms),
	    close(S)).

read_terms(S, Terms) :-
	read_term(S, T, []),
	(   T == end_of_file
	->  Terms = []
	;   Terms = [T|More],
	    read_terms(S, More)
	).

write_program(File, Terms) :-
	setup_call_cleanup(
	    open(File, write, S, [encoding(utf8)]),
	    forall(member(T, Terms), write_clause(S, T)),
	    close(S)).

write_clause(S, T) :-
	\+ \+ ( numbervars(T, 0, _),
		write_term(S, T, [quoted(true), numbervars(true), ignore_ops(false)]),
		write(S, '.'), nl(S) ).

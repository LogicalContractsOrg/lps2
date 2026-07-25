/* lps_internal_syntax.pl — writing the internal representation and the trace.

   Three writers:

     `dump_internal/2`  the §I.3 vocabulary, i.e. what upstream's `dump/0`
			produces. Round-tripping through it is the M2 gate.
     `write_lpst/4`     a trace as a `.lpst` file, in exactly the shape the
			conformance contract (§0.2) expects.
     `trace_to_lpst/2`  the same thing as a term, for callers that do not want
			a file.

   The `.lpst` writer has to be byte-compatible in one specific way: items are
   numbervar'd before being written and printed with writeq, so `'$VAR'(0)`
   comes out as `A` and reads back as a fresh variable. That is how upstream
   preserves "term shape up to variable renaming" through a file, and the
   comparison is `variant/2`, so getting it wrong shows up as a failure with
   no obvious cause.
*/

:- module(lps_internal_syntax, [
	write_lpst/4,            % +File, +Trace, +Options, +Outcome
	trace_to_lpst/2,         % +Trace, -Terms
	dump_internal/2          % +Program, +Stream
	]).

:- use_module(library(lists)).
:- use_module('../core/lps_ops').
:- use_module('../core/lps_program').
:- use_module('../core/lps_terms').

%!	trace_to_lpst(+Trace, -Terms) is det.
%
%	Trace records are `stage(Stage, Cycle, Items)` and
%	`action_ancestor(Cycle, Call, T1, T2)`. Items are already numbervar'd
%	at emission time (lps_cycle:emit/3).
trace_to_lpst(Trace, Terms) :-
	findall(T, lpst_term(Trace, T), Terms).

lpst_term(Trace, lps_test_result(Stage, Cycle, N)) :-
	member(stage(Stage, Cycle, Items), Trace),
	length(Items, N).
lpst_term(Trace, lps_test_result_item(Stage, Cycle, Item_)) :-
	member(stage(Stage, Cycle, Items), Trace),
	member(Item, Items),
	abstract_gigantic(Item, Item_).
lpst_term(Trace, lps_test_action_ancestor(Call, T1, T2)) :-
	member(action_ancestor(_, Call, T1, T2), Trace).

%	§0.2's escape hatch: an item bigger than 1000 term cells is stored as
%	its size only and matched on size alone. A few corpus tests are
%	therefore weakly checked; reproducing the threshold matters because it
%	decides *which* ones.
abstract_gigantic(Item, Out) :-
	my_term_size(Item, Size),
	(   Size > 1000
	->  Out = lps_gigantic(Size)
	;   Out = Item
	).

%!	write_lpst(+File, +Trace, +Options, +Outcome) is det.
write_lpst(File, Trace, Options, Outcome) :-
	trace_to_lpst(Trace, Terms),
	setup_call_cleanup(
	    open(File, write, S, [encoding(utf8)]),
	    write_lpst_(S, Terms, Options, Outcome),
	    close(S)).

write_lpst_(S, Terms, Options, Outcome) :-
	format(S, '/*~n  LPS(2) test results file~n*/~n~n', []),
	format(S, ':- dynamic lps_test_result/3, lps_test_result_item/3, ~n', []),
	format(S, '   lps_test_action_ancestor/3, lps_test_options/1.~n~n', []),
	writeq_term(S, lps_test_options(Options)),
	nl(S),
	forall(( member(T, Terms), T = lps_test_result(_, _, _) ), writeq_term(S, T)),
	forall(( member(T, Terms), T = lps_test_result_item(_, _, _) ), writeq_term(S, T)),
	(   Outcome == failure
	->  writeq_term(S, lps_test_result_item(end, -1, failure))
	;   true
	),
	forall(( member(T, Terms), T = lps_test_action_ancestor(_, _, _) ), writeq_term(S, T)).

%	numbervars(true) is writeq's default, so '$VAR'(0) prints as A and
%	reads back as a variable — which is what makes the variant/2 comparison
%	work across a file boundary.
writeq_term(S, T) :-
	\+ \+ ( numbervars(T, 0, _),
		write_term(S, T, [quoted(true), numbervars(true)]),
		write(S, '.'), nl(S) ).

		 /*******************************
		 *	   dump/0 (§I.3)	*
		 *******************************/

%!	dump_internal(+Program, +Stream) is det.
%
%	The internal-syntax dump. Order follows upstream's: declarations,
%	initial state, rules, then the clause families.
dump_internal(P, S) :-
	forall(dump_term(P, T), writeq_term(S, T)).

dump_term(P, maxTime(X)) :- prog_setting(P, maxTime, X).
dump_term(P, maxRealTime(X)) :- prog_setting(P, maxRealTime, X).
dump_term(P, minCycleTime(X)) :- prog_setting(P, minCycleTime, X).
dump_term(P, simulatedRealTimePerCycle(X)) :- prog_setting(P, simulatedRealTimePerCycle, X).
dump_term(P, simulatedRealTimeBeginning(X)) :- prog_setting(P, simulatedRealTimeBeginning, X).
dump_term(P, actions(L)) :- prog_decls_(P, decls(_, _, _, As, _, _, _, _)), member(L, As).
dump_term(P, action(A)) :- prog_decls_(P, decls(_, _, A1, _, _, _, _, _)), member(A, A1).
dump_term(P, fluents(L)) :- prog_decls_(P, decls(_, Fs, _, _, _, _, _, _)), member(L, Fs).
dump_term(P, fluent(F)) :- prog_decls_(P, decls(F1, _, _, _, _, _, _, _)), member(F, F1).
dump_term(P, events(L)) :- prog_decls_(P, decls(_, _, _, _, _, Es, _, _)), member(L, Es).
dump_term(P, event(E)) :- prog_decls_(P, decls(_, _, _, _, E1, _, _, _)), member(E, E1).
dump_term(P, prolog_events(L)) :- prog_decls_(P, decls(_, _, _, _, _, _, PEs, _)), member(L, PEs).
dump_term(P, unserializable(L)) :- prog_decls_(P, decls(_, _, _, _, _, _, _, Us)), member(L, Us).
dump_term(P, initial_state(L)) :- prog_initial(P, Ls), member(L, Ls).
dump_term(P, reactive_rule(A, C)) :- prog_rules(P, L), member(reactive_rule(A, C), L).
dump_term(P, reactive_rule(A, C, Pri)) :- prog_rules_pri(P, L), member(reactive_rule(A, C, Pri), L).
dump_term(P, T) :- prog_l_events_all(P, L), member(T, L).
dump_term(P, T) :- prog_l_int_all(P, L), member(T, L).
dump_term(P, T) :- prog_l_timeless_all(P, L), member(T, L).
dump_term(P, T) :- prog_initiated(P, L), member(T, L).
dump_term(P, T) :- prog_terminated(P, L), member(T, L).
dump_term(P, T) :- prog_updated(P, L), member(T, L).
dump_term(P, d_pre(C)) :- prog_d_pre(P, L), member(C, L).
dump_term(P, observe(E, T)) :- prog_observe(P, L), member(observe(E, T), L).

prog_decls_(P, D) :- arg(18, P, D).

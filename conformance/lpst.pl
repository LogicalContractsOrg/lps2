/* lpst.pl — reading `.lpst` golden/actual trace files and comparing them with
   exactly the semantics of the legacy engine's `run_test` path.

   See docs/LPSplusLLM.md §0.2 and §I.1.1. The comparison implemented here is the
   contract every future LPS2 engine must satisfy; it is deliberately a faithful
   copy of `interpreter:test/3` + `test_items_ok/2`, including their quirks:

     - the item count is checked with length/2 against the recorded N;
     - items are compared with sort/2 (duplicate-removing) on both sides, then
       variant/2 — so intra-cycle order is free but term shape is exact;
     - `lps_gigantic(Size)` items are matched on recomputed term size only;
     - the comparison is driven by the stages/cycles the *actual* run produced;
       a golden entry the actual run never reached is invisible to upstream, so we
       report it separately as a `strict` divergence rather than silently.
     - success/failure of the whole program must agree: a program that is supposed
       to fail carries `lps_test_result_item(end,-1,failure)`.
*/

:- module(lpst, [
	lpst_read/2,             % +File, -Trace
	lpst_empty/1,            % -Trace
	lpst_outcome/2,          % +Trace, -success|failure
	lpst_options/2,          % +Trace, -Options
	lpst_keys/2,             % +Trace, -ListOfStage-Cycle
	lpst_items/4,            % +Trace, +Stage, +Cycle, -Items
	lpst_compare/3,          % +Actual, +Golden, -Verdict
	lpst_size/2              % +Trace, -NumberOfItems
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
%	Trace items are written with the LPS operator table in scope, so
%	`another_day("..." at 1)` appears in a `.lpst` with `at` as an operator.
%	Reading it back without the table is a syntax error, which shows up as an
%	unexplained harness failure rather than as a mismatch.
:- use_module('../src/core/lps_ops').

/* A trace is  lpst(Options, Counts, Items, Outcome, Ancestors)  where
     Counts    : list of count(Stage,Cycle,N)          in file order
     Items     : list of items(Stage,Cycle,ItemList)   in file order, items in file order
     Outcome   : success | failure
     Ancestors : list of ancestor(Call,T1,T2)   (recorded, never compared — §I.10.5)
*/

lpst_empty(lpst([], [], [], success, [])).

%!	lpst_read(+File, -Trace) is det.
%
%	Read a .lpst file without consulting it (no side effects on the database).
%	Each fact is read independently, so variables are per-fact — which is also
%	how the legacy engine sees them after loading the file as clauses.

lpst_read(File, lpst(Options, Counts, Items, Outcome, Ancestors)) :-
	setup_call_cleanup(
		open(File, read, S, [encoding(utf8)]),
		read_all_terms(S, Terms),
		close(S)),
	collect(Terms, Options, Counts, Pairs, Outcome, Ancestors),
	group_items(Pairs, Items).

read_all_terms(S, Terms) :-
	read_term(S, T, [module(lpst)]),
	(   T == end_of_file
	->  Terms = []
	;   Terms = [T|More],
	    read_all_terms(S, More)
	).

collect([], [], [], [], success, []).
collect([T|Ts], Options, Counts, Pairs, Outcome, Ancestors) :-
	(   T = (:- _)
	->  collect(Ts, Options, Counts, Pairs, Outcome, Ancestors)
	;   T = lps_test_options(O)
	->  Options = O,
	    collect(Ts, _, Counts, Pairs, Outcome, Ancestors)
	;   T = lps_test_result(S, C, N)
	->  Counts = [count(S,C,N)|Counts1],
	    collect(Ts, Options, Counts1, Pairs, Outcome, Ancestors)
	;   T = lps_test_result_item(end, -1, failure)
	->  Outcome = failure,
	    collect(Ts, Options, Counts, Pairs, _, Ancestors)
	;   T = lps_test_result_item(S, C, Item)
	->  Pairs = [S-C-Item|Pairs1],
	    collect(Ts, Options, Counts, Pairs1, Outcome, Ancestors)
	;   T = lps_test_action_ancestor(Call, T1, T2)
	->  Ancestors = [ancestor(Call,T1,T2)|As],
	    collect(Ts, Options, Counts, Pairs, Outcome, As)
	;   collect(Ts, Options, Counts, Pairs, Outcome, Ancestors)
	).

%	Group S-C-Item triples into items(S,C,List), first-occurrence order preserved.
group_items(Pairs, Items) :-
	group_items_(Pairs, [], Items).

group_items_([], Acc, Items) :-
	reverse(Acc, Items).
group_items_([S-C-Item|Rest], Acc, Items) :-
	(   select(items(S1,C1,L), Acc, items(S1,C1,L2), Acc1),
	    S1 == S, C1 == C
	->  append(L, [Item], L2),
	    group_items_(Rest, Acc1, Items)
	;   group_items_(Rest, [items(S,C,[Item])|Acc], Items)
	).

lpst_outcome(lpst(_,_,_,O,_), O).
lpst_options(lpst(O,_,_,_,_), O).

lpst_keys(lpst(_,_,Items,_,_), Keys) :-
	findall(S-C, member(items(S,C,_), Items), Keys).

lpst_items(lpst(_,_,Items,_,_), S, C, L) :-
	(   member(items(S1,C1,L0), Items), S1 == S, C1 == C
	->  L = L0
	;   L = []
	).

lpst_count(lpst(_,Counts,_,_,_), S, C, N) :-
	member(count(S1,C1,N0), Counts), S1 == S, C1 == C, !, N = N0.

lpst_size(lpst(_,_,Items,_,_), N) :-
	foldl([items(_,_,L),A0,A]>>(length(L,K), A is A0+K), Items, 0, N).

%!	lpst_compare(+Actual, +Golden, -Verdict) is det.
%
%	Verdict = verdict(Upstream, Strict, Failures) where
%	  Upstream : pass | fail  — exactly what legacy `run_test` would conclude
%	  Strict   : pass | fail  — additionally requires that the actual run covers
%	                            every stage/cycle the golden file records
%	  Failures : list of diagnosis terms, most useful first.

lpst_compare(Actual, Golden, verdict(Upstream, Strict, Failures)) :-
	lpst_keys(Actual, AKeys),
	findall(F, (member(S-C, AKeys), key_failure(Actual, Golden, S, C, F)), KeyFailures),
	lpst_outcome(Actual, AO),
	lpst_outcome(Golden, GO),
	(   AO == GO
	->  OutcomeFailures = []
	;   OutcomeFailures = [program_failure(actual(AO), expected(GO))]
	),
	append(KeyFailures, OutcomeFailures, Failures0),
	(   Failures0 == []
	->  Upstream = pass
	;   Upstream = fail
	),
	lpst_keys(Golden, GKeys),
	findall(missing_cycle(S,C),
		( member(S-C, GKeys), \+ (member(S1-C1, AKeys), S1==S, C1==C) ),
		Missing),
	append(Failures0, Missing, Failures),
	(   Failures == []
	->  Strict = pass
	;   Strict = fail
	).

key_failure(Actual, Golden, S, C, Failure) :-
	lpst_items(Actual, S, C, A),
	(   \+ lpst_count(Golden, S, C, _)
	->  Failure = missing_fact(S, C, A)
	;   lpst_count(Golden, S, C, N),
	    length(A, NA),
	    (	NA =\= N
	    ->	Failure = count(S, C, actual(NA), expected(N))
	    ;	lpst_items(Golden, S, C, G),
		\+ items_ok(A, G),
		Failure = items(S, C, actual(A), expected(G))
	    )
	).

%	Faithful copy of interpreter:test_items_ok/2.
items_ok(Actual, Test) :-
	memberchk(lps_gigantic(_), Test), !,
	items_ok_(Actual, Test).
items_ok(Actual, Test) :-
	sort(Actual, A), sort(Test, T), A =@= T.

items_ok_([A|An], [lps_gigantic(Size)|Tn]) :- !,
	\+ \+ ( numbervars(A, 0, _), my_term_size(A, Size1), Size1 == Size ),
	items_ok_(An, Tn).
items_ok_([A|An], [T|Tn]) :- !,
	A =@= T,
	items_ok(An, Tn).
items_ok_([], []).

%	Faithful copy of interpreter:my_term_size/2.
my_term_size(T, 1) :- var(T), !.
my_term_size([T|TT], N) :- !, my_term_size(T, N1), my_term_size(TT, N2), N is N1+N2.
my_term_size([], 1) :- !.
my_term_size(T, 1) :- atomic(T), !.
my_term_size(T, N) :- T =.. [_|L], my_term_size(L, N2), N is N2+1.

/* trace_diff.pl — show, cycle by cycle, where an LPS2 trace diverges from a
   golden `.lpst`.

   The harness's verdict tells you *that* a test failed; this tells you where.
   It reads the `.lpst` the last LPS2 run left in build/work/<slug>/lps2_none/
   and the golden it was compared against, and prints the first differing
   stage/cycle with both item lists.

   Usage:
     ./myswipl.sh -q -g "consult('tools/trace_diff.pl')" -g "td:main([goat])" -t halt
*/

:- module(td, [ main/1, diff/2 ]).

:- use_module(library(lists)).
:- use_module('../src/core/lps_ops').
:- use_module('../conformance/corpus').
:- use_module('../conformance/lpst').

main([Only|_]) :-
	corpus_entries([main, extended], Entries),
	include([entry(S,_,_,_)]>>sub_atom(S, _, _, _, Only), Entries, Sel),
	forall(member(E, Sel), report(E)).

report(entry(Slug, Golden, _, _)) :-
	lps2_root(Root),
	atomic_list_concat([Root, '/build/work/', Slug, '/lps2_none'], Dir),
	(   actual_lpst(Dir, Actual)
	->  format('~n=== ~w ===~n', [Slug]),
	    diff(Actual, Golden)
	;   format('~n=== ~w: no LPS2 run found in ~w ===~n', [Slug, Dir])
	).

actual_lpst(Dir, File) :-
	exists_directory(Dir),
	directory_files(Dir, Es),
	member(E, Es),
	atom_concat(_, '.lpst', E),
	atomic_list_concat([Dir, '/', E], File), !.

%!	diff(+ActualFile, +GoldenFile) is det.
diff(ActualFile, GoldenFile) :-
	lpst_read(ActualFile, A),
	lpst_read(GoldenFile, G),
	lpst_keys(A, AK), lpst_keys(G, GK),
	append(AK, GK, K0), sort(K0, Keys0),
	sort_keys(Keys0, Keys),
	forall(member(S-C, Keys), diff_key(A, G, S, C)),
	lpst_outcome(A, AO), lpst_outcome(G, GO),
	(   AO == GO -> true
	;   format('  outcome: ours ~w, golden ~w~n', [AO, GO])
	).

%	Cycle order, then stage order — reading a trace by cycle is the whole
%	point.
sort_keys(Keys, Sorted) :-
	map_list_to_pairs(cycle_of, Keys, Pairs),
	keysort(Pairs, P1),
	pairs_values(P1, Sorted).

cycle_of(_-C, C).

diff_key(A, G, S, C) :-
	lpst_items(A, S, C, Ai),
	lpst_items(G, S, C, Gi),
	msort(Ai, As), msort(Gi, Gs),
	(   As =@= Gs
	->  true
	;   format('  ~w/~w~n', [S, C]),
	    subtract_variant(As, Gs, OnlyOurs),
	    subtract_variant(Gs, As, OnlyGolden),
	    ( OnlyOurs == [] -> true ; format('    ours only:   ~q~n', [OnlyOurs]) ),
	    ( OnlyGolden == [] -> true ; format('    golden only: ~q~n', [OnlyGolden]) )
	).

subtract_variant([], _, []).
subtract_variant([X|Xs], Ys, Out) :-
	(   member(Y, Ys), X =@= Y
	->  Out = Out1
	;   Out = [X|Out1]
	),
	subtract_variant(Xs, Ys, Out1).

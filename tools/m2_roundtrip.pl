/* m2_roundtrip.pl — the M2 gate.

   > M2 gate: `legacy → internal → dump` matches upstream `dump/0`.

   Implemented as the strongest cheap version of that: translate every corpus
   program's *surface* source with src/syntax/lps_legacy_syntax.pl and compare,
   term by term, against the `_.P` that psyntax generated from the same file.

   Comparison is `=@=` (variant), the same criterion the `.lpst` contract uses:
   variable *names* are free, everything else — term shape, argument order and
   above all **clause order**, which is selection order (selection_spec SP3) —
   is exact.

   The staged `_.P` under build/work/<slug>/base/ is the target rather than the
   one in legacy_lps1/examples/, because the harness regenerates it first and
   some checked-in ones are older than their sources.

   Usage:
     ./myswipl.sh -q -g "consult('tools/m2_roundtrip.pl')" -g "m2:main" -t halt
     ... -g "m2:main(['--only', goat])"
*/

:- module(m2, [ main/0, main/1, compare_one/3 ]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../src/core/lps_ops').
:- use_module('../src/core/lps_diag').
:- use_module('../src/syntax/lps_legacy_syntax').
:- use_module('../src/edges/lps_source').
:- use_module('../conformance/corpus').
:- use_module('../conformance/adapter_legacy').

main :- main([]).

main(Argv) :-
	(   append(_, ['--only', Only|_], Argv) -> true ; Only = '' ),
	corpus_entries([main], Entries),
	include(has_source, Entries, WithSource),
	include(selected(Only), WithSource, Selected),
	maplist(check, Selected, Results),
	summarise(Results).

has_source(entry(_, _, _, Source)) :- Source \== none.
selected('', _) :- !.
selected(Only, entry(Slug, _, _, _)) :- sub_atom(Slug, _, _, _, Only).

/* One corpus program is *expected* to differ, and it is upstream's bug, not
   ours. psyntax pretty-prints a clause body conjunct by conjunct and writes
   the last one with plain write_term, so a trailing if-then-else loses its
   parentheses:

     source     ..., PY is Y+10, (P=dad -> PX is X+25 ; PX is X+50).
     generated  ..., PY is Y+10, P=dad -> PX is X+25 ; PX is X+50.

   which re-reads as ((..., P=dad) -> ... ; ...) — a different clause. The
   engine runs the *generated* file, so badlight's golden trace reflects the
   corrupted form and conformance is unaffected; reproducing the bug in our
   own writer would be the wrong fix.
*/
adjudicated('CLOUT_workshop_badlight.pl',
	    'psyntax drops the parentheses around a trailing if-then-else in a\c
	     pass-through Prolog clause; the generated _.P is not equivalent to\c
	     its source. Upstream defect, not a translation difference.').

check(Entry, result(Slug, Verdict)) :-
	Entry = entry(Slug, _, _, Source),
	%  Stage first, so the `_.P` we compare against is the regenerated one.
	(   catch(legacy_stage(Entry, StagedP), _, fail)
	->  compare_one(Source, StagedP, Verdict)
	;   Verdict = not_staged
	),
	(   Verdict == ok
	->  format('~w~t~60| ok~n', [Slug])
	;   adjudicated(Slug, _)
	->  format('~w~t~60| differs (adjudicated: upstream writer bug)~n', [Slug])
	;   format('~w~t~60| ~q~n', [Slug, Verdict])
	),
	flush_output.

%!	compare_one(+SurfaceFile, +GeneratedP, -Verdict) is det.
compare_one(Source, Generated, Verdict) :-
	legacy_to_internal(file(Source), [], Ours0, Diags),
	(   diags_ok(Diags)
	->  maplist([t(T,_), T]>>true, Ours0, Ours),
	    lps_read_terms(Generated, Theirs0, _),
	    maplist([t(T,_), T]>>true, Theirs0, Theirs),
	    compare_terms(Ours, Theirs, 1, Verdict)
	;   length(Diags, N),
	    Diags = [D|_], diag_message(D, M),
	    Verdict = translation_errors(N, M)
	).

compare_terms([], [], _, ok) :- !.
compare_terms([], [T|_], N, missing_at(N, T)) :- !.
compare_terms([T|_], [], N, extra_at(N, T)) :- !.
compare_terms([A|As], [B|Bs], N, Verdict) :-
	(   A =@= B
	->  N1 is N + 1, compare_terms(As, Bs, N1, Verdict)
	;   Verdict = differs_at(N, ours(A), theirs(B))
	).

summarise(Results) :-
	length(Results, N),
	include([result(_, ok)]>>true, Results, Ok),
	length(Ok, NOk),
	findall(S, ( member(result(S, V), Results), V \== ok, adjudicated(S, _) ), Adj),
	length(Adj, NAdj),
	findall(S, ( member(result(S, V), Results), V \== ok, \+ adjudicated(S, _) ), Bad),
	length(Bad, NBad),
	format('~n=== M2 round-trip ===~n', []),
	format('  identical to psyntax   ~w/~w~n', [NOk, N]),
	format('  adjudicated upstream   ~w~n', [NAdj]),
	format('  unexplained            ~w~n', [NBad]),
	forall(member(S, Adj),
	       ( adjudicated(S, Why), format('~n  ~w~n    ~w~n', [S, Why]) )),
	(   Bad == []
	->  true
	;   format('~ndifferences:~n', []),
	    forall(( member(result(S2, V2), Results), member(S2, Bad) ),
		   ( format(atom(A), '~q', [V2]),
		     sub_atom_upto(A, 220, A1),
		     format('  ~w~n    ~w~n', [S2, A1]) ))
	).

sub_atom_upto(A, Max, Out) :-
	atom_length(A, L),
	(   L =< Max -> Out = A
	;   sub_atom(A, 0, Max, _, P), atom_concat(P, ' …', Out)
	).

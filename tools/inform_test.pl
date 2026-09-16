/* inform_test.pl — the phase-4 gate of docs/project/plans/InformPlan.md.
 *
 * Eleven Inform 7 programs (examples/if/inform/, see NOTICE.md) go through
 * src/syntax/lps_inform.pl into Logical English stories on the library,
 * written to build/inform_out/ beside a copy of world.le. Each is then run
 * as a story and checked three ways:
 *
 *   1. it compiles and its `Test me with` script runs to `success`;
 *   2. its initial state holds the facts read by hand from the assertions
 *      (§IV.5: the oracle is specified before the transpiler is trusted);
 *   3. where a hand-written story of the same program exists and the
 *      program has no rules of its own, the event sequence equals the one
 *      the hand-written story was checked against Inform's transcript with.
 *
 *   LPS_LE2_LIB=/LogicalEnglish2 tools/inform_test.sh        # one program per process
 *   LPS_LE2_LIB=/LogicalEnglish2 ./myswipl.sh -q -g "consult('tools/inform_test.pl')" -g "inform_test:main" -t halt
 *
 * The shell script is the one to run: all eleven in one process want more
 * memory than a small container has.
 */

:- module(inform_test, [main/0, one/1]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../src/lps').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_program').
:- use_module('../src/core/lps_diag').
:- use_module('../src/edges/lps_cli').
:- use_module('../src/syntax/lps_inform').

outdir('build/inform_out').

%!	expect(?Source, ?InitialFluents, ?TimelessFacts, ?HandWritten)
%
%	What the assertions say, read by hand. HandWritten names the story in
%	examples/if/ whose recorded events the generated one must reproduce, or
%	`none` when the program has rules the front end does not translate.
expect('ImplicitConnections', [in(player, temple)],
       [is_a_room(temple), is_a_room(approach), is_a_room(sphinx),
	from_goes_to(north, temple, approach), from_goes_to(east, temple, sphinx)],
       implicit_connections).
expect('NothingAsTerm', [in(player, home), carries(player, box), in(banana, box), in(peach, box)],
       [is_a_room(home)],
       nothing_as_term).
expect('NegatedRP', [in(player, start), in(jewel_box, start), closed(jewel_box),
		     in(broken_box, start), closed(broken_box), in(secret_box, start), closed(secret_box)],
       [is_a_container(jewel_box), is_openable(jewel_box), is_a_container(broken_box),
	is_a_container(secret_box)],
       negated_rp).
expect('NPCGoingTwistily', [in(thief, twisty_passage), in(player, twisted_passage)],
       [is_a_room(twisty_passage), is_a_room(twisted_passage),
	from_goes_to(east, twisted_passage, twisty_passage), from_goes_to(east, twisty_passage, twisted_passage)],
       none).
expect('Regarding', [in(player, foo), in(torch, foo), in(banana, foo), in(grapes, foo)],
       [is_a_room(foo)], none).
expect('GoingSouthIn', [in(player, home)],
       [is_a_room(home), is_a_room(garden), from_goes_to(south, home, garden)], none).
expect('TakingInventory', [in(player, place), in(inventory, place)], [is_a_room(place)], none).
expect('C9SceneEndSequence', [in(player, home), in(cube, home), in(ball, home)], [is_a_room(home)], none).
expect('IQTest', [in(player, donut_shop), in(ogg, donut_shop), in(case, donut_shop), closed(case),
		  locked(case), in(cake_donuts, case), carries(ogg, silver_key), wears(ogg, nametag)],
       [is_a_room(donut_shop), is_a_person(ogg), is_a_container(case), is_openable(case),
	is_lockable(case), the_key_of_is(case, silver_key), is_edible(cake_donuts)],
       none).
expect('BostonCream', [in(player, donut_shop), in(ogg, donut_shop), in(case, donut_shop), closed(case),
		       locked(case), in(cake_donuts, case), in(jelly_donuts, case), in(apple_fritters, case),
		       in(mesh_basket, donut_shop), closed(mesh_basket), in(silver_key, mesh_basket)],
       [is_a_container(case), is_enterable(case), is_fixed_in_place(case), the_key_of_is(case, silver_key),
	is_a_container(mesh_basket), is_openable(mesh_basket)],
       none).
expect('MRE', [in(player, base_camp_larder), in(apple, base_camp_larder), in(candy_bar, base_camp_larder),
	       in(large_plate_of_pasta, base_camp_larder)],
       [is_a_room(base_camp_larder)], none).

main :-
	format('~n=== Phase 4: Inform assertions as stories ===~n~n', []),
	(   getenv('LPS_LE2_LIB', _) -> true
	;   format('LPS_LE2_LIB is not set: the stories are Logical English.~n', []), halt(1)
	),
	prepare,
	findall(R, ( expect(S, Fs, Ts, Hand), once(check_one(S, Fs, Ts, Hand, R)) ), Rs),
	include(==(ok), Rs, Oks),
	length(Rs, N), length(Oks, NOk),
	format('~n=== ~w/~w Inform programs translate, run and hold their assertions ===~n', [NOk, N]),
	( NOk =:= N -> true ; halt(1) ).

%!	one(+Source) is det.
%
%	One program, for a shell loop that runs each in its own process — the
%	eleven translations through LE2 in one process want more memory than a
%	small container has.
one(Source) :-
	prepare,
	expect(Source, Fs, Ts, Hand),
	once(check_one(Source, Fs, Ts, Hand, R)),
	( R == ok -> true ; halt(1) ).

prepare :-
	outdir(Dir), make_directory_path(Dir),
	atomic_list_concat([Dir, '/world.le'], W),
	read_file_to_string('examples/if/world.le', WT, [encoding(utf8)]),
	write_text(W, WT).

write_text(File, Text) :-
	setup_call_cleanup(open(File, write, S, [encoding(utf8)]), write(S, Text), close(S)).

check_one(Source, Fluents, Timeless, Hand, R) :-
	atomic_list_concat(['examples/if/inform/', Source, '.ni'], Path),
	inform_to_le(Path, LE, Companion, Diags),
	lps_inform:story_name(Source, Name),
	outdir(Dir),
	atomic_list_concat([Dir, '/', Name, '.le'], LEFile),
	atomic_list_concat([Dir, '/', Name, '.lps'], CFile),
	write_text(LEFile, LE), write_text(CFile, Companion),
	length(Diags, ND),
	(   catch(trace_of(LEFile, P, Trace, Status), E, ( Status = E, Trace = [], P = none ))
	->  true
	;   Status = failed_to_run, Trace = [], P = none
	),
	(   Status \== success
	->  R = failed, format('  FAIL  ~w~t~26| ~q~n', [Source, Status])
	;   missing_initial(Trace, Fluents, MF),
	    missing_timeless(P, Timeless, MT),
	    ( Hand == none -> HandOk = true ; hand_matches(Trace, Hand, HandOk) ),
	    (   MF == [], MT == [], HandOk == true
	    ->  R = ok, format('  ok    ~w~t~26| ~w diagnostics~n', [Source, ND])
	    ;   R = failed,
		format('  FAIL  ~w~t~26| missing initial ~q, missing timeless ~q, hand-written ~w~n',
		       [Source, MF, MT, HandOk])
	    )
	).

trace_of(Path, P, Trace, Status) :-
	lps_cli:compile_source(le, Path, [], P, Diags),
	( diags_ok(Diags) -> true ; throw(diagnostics(Diags)) ),
	lps_session_new(P, [dc], S0),
	lps_session_run(S0, end, S, Trace),
	lps_session_status(S, Status).

%	No lambdas here: yall copies a lambda's free variables, and a check
%	against a copied Init or P is a check against nothing.
missing_initial(Trace, Fluents, Missing) :-
	( memberchk(stage(fluents, 0, Init), Trace) -> true ; Init = [] ),
	findall(F, ( member(F, Fluents), \+ memberchk(F, Init) ), Missing).

missing_timeless(P, Facts, Missing) :-
	findall(F, ( member(F, Facts), \+ catch(p_call(P, F), _, fail) ), Missing).

%	The hand-written story's recorded events, cycle for cycle.
hand_matches(Trace, Hand, Ok) :-
	atomic_list_concat(['examples/if/expected/', Hand, '.pl'], Path),
	read_file_to_terms(Path, Terms, []),
	findall(C-Is, member(events(C, Is), Terms), Expected),
	findall(C-Is, ( member(stage(events, C, Is), Trace), Is \== [] ), Got),
	(   same_events(Got, Expected) -> Ok = true
	;   first_difference(Got, Expected, Ok)
	).

same_events(A, B) :-
	length(A, N), length(B, N),
	forall(nth1(I, A, C-Is), ( nth1(I, B, C-Js), msort(Is, S1), msort(Js, S2), S1 =@= S2 )).

first_difference(A, B, differs(cycle(C), got(Is), expected(Js))) :-
	nth1(I, A, C-Is), ( nth1(I, B, _-Js) -> true ; Js = none ),
	\+ ( nth1(I, B, C-Js), msort(Is, S1), msort(Js, S2), S1 =@= S2 ), !.
first_difference(A, B, length(got(NA), expected(NB))) :- length(A, NA), length(B, NB).

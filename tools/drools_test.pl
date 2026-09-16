/* drools_test.pl — the M12d gate.
 *
 * §IV.5 says every transpiler needs its own oracle, and names the one for
 * Drools: "agreement on which rules fire in which order". The real thing is a
 * Java harness running the same scenario through a KieSession with an
 * AgendaEventListener; that needs a JVM, and this container has none, so the
 * oracle here is the next thing down — **the expected firing sequence,
 * written out by hand from the rule base's documented behaviour and checked
 * in beside it**.
 *
 * That is weaker than differential testing against Drools and it is honest
 * about being weaker: it catches a translation that fires the wrong rule, in
 * the wrong order, or on the wrong facts, and it does not catch a shared
 * misunderstanding of what Drools would do. Building the Java side is the
 * first thing to do when a JVM is available (§IV.6).
 *
 *   ./myswipl.sh -q -g "consult('tools/drools_test.pl')" -g "drools_test:main" -t halt
 */

:- module(drools_test, [main/0]).

:- use_module(library(lists)).
:- use_module(library(terms), [variant/2]).
:- use_module(library(aggregate)).
:- use_module(library(yall)).
:- use_module('../src/lps').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_diag').
:- use_module('../src/syntax/lps_drools').

/* case(File, InitialFacts, ExpectedFirings, ExpectedDiagnostics).
 *
 * File is a rule base of examples/migration/drools/drl/ or of
 * tools/drools_fixtures/ (the constructs that are not examples); a name
 * with a `-suffix` is the same file with other facts.
 *
 * ExpectedFirings is the sequence of *actions* (rule consequences), one list
 * per cycle, ignoring cycles in which nothing fired.
 */
case('fire-alarm',
     [fire(kitchen), sprinkler(kitchen, false), sprinkler(office, false)],
     [[alarm_goes_on, sprinkler_turns_on(kitchen)]],
     0).
case('fire-alarm-out',
     [alarm(yes)],
     [[alarm_goes_off]],
     0).
case('discount',
     [order(acme, large), customer(acme, gold)],
     [[discount_starts(acme, best)]],
     2).                     % two salience warnings
case('discount-standard',
     [order(zeta, large), customer(zeta, silver)],
     [[discount_starts(zeta, standard)]],
     2).
%  A state machine: three rules that hand the light on round the cycle. The
%  same shape LPS is for, which is why it is here — and `modify` lands on
%  `updated/4`, the same term `updates … to … in …` produces.
%  It goes round for as long as the run lasts, which is the point of a state
%  machine: six cycles of maxTime(6) give five transitions. `modify` changes
%  the fact the rule matched — the light called gate — so each action names
%  it (it used to carry a fresh variable: the modify built its own copy of
%  the pattern instead of using the matched one).
case('traffic-light', [light(gate, green), tick(1)], Firings, 0) :-
	Firings = [[light_colour_becomes(amber)], [light_colour_becomes(red)],
		   [light_colour_becomes(green)], [light_colour_becomes(amber)],
		   [light_colour_becomes(red)]].
%  `not` over a pattern, in both languages, and the reason "no policy yet" needs
%  no flag.
case('insurance',
     [driver(ann, young, clean), driver(bob, mature, clean)],
     [[policy_starts(bob, low), policy_starts(ann, high)]],
     0).
%  A claim demotes an existing low band. Two cycles: the classification is
%  already there, so only the third rule can fire.
case('insurance-claim',
     [driver(cid, mature, claimed), policy(cid, low)],
     [[policy_band_becomes(cid, standard)]],
     0).
%  `retract` of a *pattern variable*, which is the case the generic path got
%  wrong: it made an action named after the variable that terminated nothing,
%  so the rule fired for ever and the fact stayed.
case('shipping',
     [order(o1, placed), stock(widget, available)],
     [[shipment_starts(o1), order_state_becomes(o1, shipped), stock_level_becomes(low)],
      [order_ends(o1, shipped)]],
     0).

%  The fixtures (tools/drools_fixtures/): one construct each.
%  `or` between patterns is one rule per alternative (ann is young, cy old);
%  `not( A or B )` is not A and not B, so the day is quiet only without both.
case('or',
     [person(ann, 10), person(bob, 40), person(cy, 70), day(monday)],
     [[flag_starts(ann), flag_starts(cy)]],
     0).
case('or-quiet',
     [person(bob, 40), day(monday)],
     [[quiet_starts(monday)]],
     0).
%  accumulate: a sum and a count over the state.
case('accumulate',
     [order(a, 60), order(b, 50)],
     [[big_starts(110), many_starts(2)]],
     0).
%  insertLogical: the room is lit while its light is on, so once the light
%  goes off it is dark. (Read as an ordinary insert, `lit` would stay and the
%  room would never be dark.)
case('logical',
     [light(hall, true)],
     [[light_turns_off(hall)], [dark_starts(hall)]],
     0).
%  a comparison under `not`: nobody over 65, not nobody at all.
case('negcompare',
     [room(r1), person(ann, 30)],
     [[calm_starts(r1)]],
     0).
case('negcompare-old',
     [room(r1), person(ann, 70)],
     [],
     0).
%  Java beside a change: the change, and the external action in the Java's
%  place (one warning).
case('java',
     [fire(kitchen)],
     [[alarm_starts(kitchen), java_leaf('raise the alarm')]],
     1).
%  Three rules not translated (three warnings), the fourth fires.
case('unsupported',
     [order(o1, 20)],
     [[flag_starts(o1)]],
     3).

%  Rule attributes, against Drools 10 on the same facts. `cap the balance`
%  (no-loop: the condition that its change is not made already) and `flag an
%  overdrawn account` (lock-on-active, read as no-loop) fire once, as in
%  Drools; `switched off` (enabled false) is left out. What is not
%  translated is a warning each and fires where Drools does not: `count
%  once` (no-loop over `count + 1`) counts on, and `in a group` (agenda-group,
%  date-expires, timer) fires. Five warnings.
case('attributes',
     [account(a, 150, false), account(b, -5, false), account(c, 0, false), counter(k, 0)],
     [[account_balance_becomes(a, 100), account_becomes_flagged(b, -5), counter_count_becomes(1), note_starts],
      [counter_count_becomes(2)], [counter_count_becomes(3)], [counter_count_becomes(4)],
      [counter_count_becomes(5)]],
     5).
%  Values computed in Java, against Drools 10: `$total.intValue()`, `$c.getCount()
%  + 1` and `$p.getName()` are read, so Big(110), the counter up to 3 and
%  Label(ann, minor) are where Drools puts them; `$p.getName().toUpperCase()`
%  is not, and its insert is Java (java_leaf and two warnings), never a
%  constant.
case('values',
     [order(o1, 60), order(o2, 50), counter(k, 0), person(ann, 10), person(bob, 40)],
     [[big_starts(110), counter_count_becomes(1), java_leaf('shout an adult\'s name'), label_starts(ann, minor)],
      [counter_count_becomes(2), java_leaf('shout an adult\'s name')],
      [counter_count_becomes(3), java_leaf('shout an adult\'s name')],
      [java_leaf('shout an adult\'s name')]],
     2).

%	Which DRL file a case uses (several cases share one rule base, with
%	different initial working memories).
file_of(Case, File) :-
	(   sub_atom(Case, B, _, _, '-'), sub_atom(Case, 0, B, _, Base),
	    exists_drl(Base)
	->  File = Base
	;   File = Case
	).

exists_drl(Base) :-
	drl_path(Base, P),
	exists_file(P).

drl_path(Base, P) :-
	(   atomic_list_concat(['examples/migration/drools/drl/', Base, '.drl'], P), exists_file(P)
	->  true
	;   atomic_list_concat(['tools/drools_fixtures/', Base, '.drl'], P)
	).

main :-
	format('~n=== M12d: Drools DRL through LPS2 ===~n~n', []),
	findall(R, ( case(C, Facts, Expected, NDiag), run_case(C, Facts, Expected, NDiag, R) ), Rs),
	include(==(ok), Rs, Oks),
	length(Rs, N), length(Oks, NOk),
	format('~n=== ~w/~w rule bases behave as expected ===~n~n', [NOk, N]),
	findall(R, ( reading_check(C, File, Opts, Goal), run_check(C, File, Opts, Goal, R) ), Cs),
	include(==(ok), Cs, COks),
	length(Cs, NC), length(COks, NCOk),
	format('~n=== ~w/~w readings are as expected ===~n', [NCOk, NC]),
	( NOk =:= N, NCOk =:= NC -> true ; halt(1) ).

/* reading_check(Name, File, Options, Goal): what a rule base reads as, with
   no working memory (File ▸ Open) unless Options say otherwise. Goal is
   called with Terms (the program's terms, without provenance) and Diags.
*/
reading_check('a compared field is kept with no facts',
	      'examples/migration/drools/drl/discount.drl', [],
	      [Ts, Ds]>>( memberchk(fluents(Fs), Ts), memberchk(customer(_, _), Fs),
			  memberchk(order(_, _), Fs),
			  \+ memberchk(diag(_, drools_field_dropped, _, _, _), Ds),
			  member(reactive_rule(C, _, 5), Ts),
			  memberchk(holds(not(customer(_, gold)), _), C) )).
reading_check('a field every inserted fact gives one value is still left out',
	      'examples/migration/drools/drl/fire-alarm.drl', [],
	      [Ts, _]>>( memberchk(fluents(Fs), Ts), memberchk(alarm, Fs) )).
reading_check('insertLogical is an intensional fluent',
	      'tools/drools_fixtures/logical.drl', [],
	      [Ts, _]>>( memberchk(l_int(holds(lit(_), _), _), Ts),
			 \+ ( memberchk(actions(As), Ts), member(A, As), functor(A, lit_starts, _) ) )).
reading_check('insertLogical of a type the working memory holds is an insert, with a warning',
	      'tools/drools_fixtures/logical.drl', [facts([light(hall, true), lit(hall)])],
	      [Ts, Ds]>>( \+ memberchk(l_int(_, _), Ts),
			  memberchk(diag(warning, drools_insert_logical, _, _, _), Ds) )).
reading_check('a type with no declare takes its fields from the Java, with a warning',
	      'tools/drools_fixtures/undeclared.drl', [],
	      [Ts, Ds]>>( memberchk(fluents(Fs), Ts), memberchk(politician(_), Fs),
			  memberchk(diag(warning, drools_undeclared_type, _, _, _), Ds) )).
reading_check('rules not translated are reported and left out',
	      'tools/drools_fixtures/unsupported.drl', [],
	      [Ts, Ds]>>( aggregate_all(count, member(diag(warning, drools_untranslated, _, _, _), Ds), 3),
			  aggregate_all(count, ( member(R, Ts), functor(R, reactive_rule, _) ), 1) )).
reading_check('an `or` is one rule per alternative',
	      'tools/drools_fixtures/or.drl', [],
	      [Ts, Ds]>>( aggregate_all(count, ( member(reactive_rule(_, [happens(flag_starts(_), _, _)]), Ts) ), 2),
			  memberchk(diag(info, drools_or, _, _, _), Ds) )).

reading_check('enabled false leaves the rule out, with a note',
	      'tools/drools_fixtures/attributes.drl', [],
	      [Ts, Ds]>>( memberchk(diag(info, drools_disabled, _, _, _), Ds),
			  aggregate_all(count, member(reactive_rule(_, [happens(note_starts, _, _)]), Ts), 1),
			  %  (and shapes nothing: every note left is "empty")
			  memberchk(diag(info, drools_field_dropped, _, 'every note has text empty, so the field tells no two of them apart: the reading leaves it out', _), Ds) )).
reading_check('no-loop is the condition that the change is not made already',
	      'tools/drools_fixtures/attributes.drl', [],
	      [Ts, Ds]>>( member(reactive_rule(C, [happens(E, _, _)]), Ts), functor(E, account_balance_becomes, _),
			  E = account_balance_becomes(_, 100), member(holds(account(_, B), _), C),
			  member(G, C), G == (B \= 100),
			  memberchk(diag(info, drools_no_loop, _, _, _), Ds) )).
reading_check('each ignored attribute is a warning',
	      'tools/drools_fixtures/attributes.drl', [],
	      [_, Ds]>>( aggregate_all(count, member(diag(warning, drools_attribute, _, _, _), Ds), 5) )).
reading_check('a value computed in Java is computed, never a constant',
	      'tools/drools_fixtures/values.drl', [],
	      [Ts, Ds]>>( member(reactive_rule(C, [happens(counter_count_becomes(_, N), _, _)]), Ts),
			  member(holds(counter(_, Old), _), C), member(G, C), G = (N0 is Old0 + 1), N0 == N, Old0 == Old,
			  member(reactive_rule(C2, [happens(big_starts(Tot), _, _)]), Ts), member(sum_list(_, S), C2), S == Tot,
			  \+ ( member(T, Ts), sub_term(R, T), compound(R), functor(R, ref, 2) ),
			  memberchk(diag(warning, drools_java_leaf, _, _, _), Ds) )).

run_check(Name, File, Opts, Goal, Result) :-
	drl_reading(File, Opts, reading(Terms0, Diags, _)),
	findall(T, member(t(T, _), Terms0), Terms),
	(   catch(call(Goal, Terms, Diags), E, ( print_message(error, E), fail ))
	->  Result = ok
	;   Result = failed
	),
	format('~w~t~72| ~w~n', [Name, Result]).

run_case(Case, Facts0, Expected, NDiag, Result) :-
	file_of(Case, Base),
	drl_path(Base, File),
	%  The facts are Drools facts; the program is the world reading of the
	%  rule base (a boolean field a state of its own, a field every fact
	%  gives one value left out), so they are read the same way. Its
	%  diagnostics are counted without the informational ones.
	drl_reading(File, [facts(Facts0)], reading(Terms0, Diags0, World)),
	drl_world_facts(World, Facts0, Facts),
	exclude([diag(info, _, _, _, _)]>>true, Diags0, Diags),
	length(Diags, ND),
	append(Terms0, [t(initial_state(Facts), src(File, 1, 0, drl)),
			t(maxTime(6), src(File, 1, 0, drl))], Terms),
	lps_compile(terms(Terms), internal, [dc], Program, CDiags),
	(   diags_ok(CDiags)
	->  lps_session_new(Program, [dc], S0),
	    lps_session_run(S0, end, _, Trace),
	    findall(Sorted, ( member(stage(events, C, Items), Trace), Items \== [], C > 1,
			      msort(Items, Sorted) ), Firings0),
	    dedupe_consecutive(Firings0, Firings),
	    maplist(msort, Expected, ExpectedSorted),
	    %  Not `==`: an action argument the rule leaves unbound reaches the
	    %  trace as a fresh variable — and sometimes as a '$VAR' term, because
	    %  the internal-syntax reader names its variables. Numbering both
	    %  sides makes an expectation written with `_` right rather than
	    %  nearly right, and does not weaken the comparison: two terms that
	    %  number to the same thing differ only in variable identity.
	    (	same_shape(Firings, ExpectedSorted), ND =:= NDiag
	    ->	Result = ok, Verdict = ok
	    ;	Result = failed,
		format(atom(Verdict), 'expected ~q + ~w diags, got ~q + ~w diags',
		       [ExpectedSorted, NDiag, Firings, ND])
	    )
	;   Result = failed, Verdict = 'does not compile'
	),
	format('~w~t~24| ~w~n', [Case, Verdict]).

same_shape(A, B) :-
	\+ \+ ( copy_term(A-B, A2-B2),
		numbervars(A2, 0, _), numbervars(B2, 0, _),
		A2 == B2 ).

%	A rule that stays satisfied fires once in LPS and once in Drools; the
%	engine re-posts the same action each cycle while its condition holds,
%	so consecutive identical cycles are one firing.
dedupe_consecutive([], []).
dedupe_consecutive([X], [X]) :- !.
dedupe_consecutive([X, X|T], Out) :- !, dedupe_consecutive([X|T], Out).
dedupe_consecutive([X|T], [X|Out]) :- dedupe_consecutive(T, Out).

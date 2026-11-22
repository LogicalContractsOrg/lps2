/* wording_test.pl — the labels of the timeline, in Logical English.

   A term of a run is said in the words of its document's template
   (src/edges/lps_wording.pl), and the `timeline` operation sends those words
   beside each label (`english`, lps_api.pl). Two halves:

     1. the wording itself, from templates written out here. This half needs
        no Logical English, and it runs everywhere;
     2. the reply of `timeline` for a Logical English example, for a program
        in the older syntax, and for a document with a default. This half
        needs LE2 loaded into this process (LPS_LE2_LIB), and without it the
        test says so and skips it.

   Usage:
     LPS_LE2_LIB=/LogicalEnglish2 ./myswipl.sh -q -g "consult('tools/wording_test.pl')" -g "wording_test:main" -t halt
*/

:- module(wording_test, [main/0]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../src/edges/lps_api').
:- use_module('../src/edges/lps_le').
:- use_module('../src/edges/lps_wording').

:- dynamic failed/1.

main :-
	retractall(failed(_)),
	wording_cases,
	(   lps_le_available(lib(_))
	->  timeline_cases
	;   format('  SKIP  the timeline replies: Logical English is not loaded here (set LPS_LE2_LIB)~n')
	),
	aggregate_all(count, failed(_), NF),
	format('~n=== wording: ~w failed ===~n', [NF]),
	( NF =:= 0 -> true ; halt(1) ).

check(Name, Goal) :-
	(   catch(Goal, E, ( print_message(error, E), fail ))
	->  format('  ok    ~w~n', [Name])
	;   format('  FAIL  ~w~n', [Name]), assertz(failed(Name))
	).

		 /*******************************
		 *	   the wording		*
		 *******************************/

templates([
	le_template(transfer/3, action, "*a payer* transfers *a amount* to *a payee*",
		    [slot(0, payer), slot(1, amount), slot(2, payee)], pos(213, 257, 9, 4), []),
	le_template(balance/2, fluent, "the balance of *a person* is *a amount*",
		    [slot(0, person), slot(1, amount)], pos(300, 340, 12, 4), []),
	le_template(gameOver/0, fluent, "the game is over", [], pos(732, 748, 21, 4), []),
	le_template(row/2, action, "farmer rows from *a first place* to *a second place*",
		    [slot(0, 'first place'), slot(1, 'second place')], pos(358, 410, 13, 4), []),
	%  two templates for one name: the one the document declares first wins
	le_template(says/2, event, "*a person* utters *a text*",
		    [slot(0, person), slot(1, text)], pos(900, 930, 30, 4), []),
	le_template(says/2, event, "*a person* says *a text*",
		    [slot(0, person), slot(1, text)], pos(800, 830, 28, 4), []),
	%  a timeless predicate and a built-in: no term of a trace is one
	le_template(beats/2, predicate, "*a choice* beats *a another choice*",
		    [slot(0, choice), slot(1, 'another choice')], pos(949, 982, 27, 4), []),
	le_template(le_lt/2, predicate, "*a number* < *a number*",
		    [slot(0, number), slot(1, number)], pos(none, none, 0, 0), [])
    ]).

wording_cases :-
	templates(Ts),
	lps_wording(Ts, W),
	check('an action, its arguments in the order of the slots',
	      ( lps_worded(W, transfer(bob, 10, alice), S1), S1 == "bob transfers 10 to alice" )),
	check('a fluent',
	      ( lps_worded(W, balance(bob, 90), S2), S2 == "the balance of bob is 90" )),
	check('a template with no slot',
	      ( lps_worded(W, gameOver, S3), S3 == "the game is over" )),
	check('a template that begins with a word',
	      ( lps_worded(W, row(south, north), S4), S4 == "farmer rows from south to north" )),
	check('a list keeps its brackets and a string its quotes',
	      ( lps_worded(W, says(ann, "hello"), S5), S5 == "ann says \"hello\"",
		lps_worded(W, transfer(bob, 5, [ann, carl]), S6), S6 == "bob transfers 5 to [ann, carl]" )),
	check('of two templates for one name, the first in the document',
	      ( lps_worded(W, says(ann, hi), S7), S7 == "ann says hi" )),
	check('a variable is written as an ellipsis (the line of a default)',
	      ( lps_worded(W, balance(_, 0), S8), S8 == "the balance of … is 0" )),
	check('no template: no wording',
	      ( \+ lps_worded(W, unknown(a), _), \+ lps_worded(W, transfer(a, b), _) )),
	check('a timeless predicate and a built-in have no wording',
	      ( \+ lps_worded(W, beats(rock, scissors), _), \+ lps_worded(W, le_lt(1, 2), _) )),
	check('no templates: no wording at all',
	      ( lps_wording([], W0), W0 == [] )).

		 /*******************************
		 *	the timeline's reply	*
		 *******************************/

timeline_cases :-
	timeline_of('examples/le/bank_transfer.le', T1),
	check('a Logical English document: the reply has `english`',
	      ( get_dict(english, T1, E1), E1 \== [] )),
	check('an action of the run, in the words of its template',
	      english_of(T1, "transfer(bob,10,fariba)", "bob transfers 10 to fariba")),
	check('every fluent lane has its sentence',
	      forall(( member(L, T1.fluents), get_dict(fluent, L, F) ), english_of(T1, F, _))),
	check('the labels themselves stay terms',
	      ( get_dict(fluents, T1, Ls), member(L1, Ls), get_dict(fluent, L1, "balance(bob,50)") )),
	timeline_of('examples/le/token.le', T2),
	check('the line of a default has its sentence',
	      ( get_dict(defaults, T2, Ds), member(D, Ds), english_of(T2, D, "the balance of … is 0") )),
	check('a refused call has its sentence',
	      ( get_dict(refused, T2, Rs), member(R, Rs), get_dict(items, R, Is), member(I, Is),
		english_of(T2, I, _) )),
	timeline_of('examples/start/cafe.lps', T3),
	check('a program in the older syntax: no `english`, its labels are terms',
	      \+ get_dict(english, T3, _)).

english_of(Timeline, Term, English) :-
	get_dict(english, Timeline, Pairs),
	member(P, Pairs), get_dict(term, P, Term0), Term0 == Term, !,
	get_dict(english, P, English).

%	Compile File as the editor does, run it to its end, and ask for the
%	timeline of the run.
timeline_of(File, Timeline) :-
	read_file_to_string(File, Source, []),
	(   file_name_extension(_, le, File)
	->  Request = _{operation: "le_compile", source: Source, name: File}
	;   Request = _{operation: "compile", source: Source, syntax: "legacy", name: File}
	),
	lps_api:handle(Request, Compiled),
	lps_api:handle(_{operation: "session_new", program: Compiled.program}, New),
	lps_api:handle(_{operation: "run", session: New.session}, _),
	lps_api:handle(_{operation: "timeline", session: New.session}, Timeline).

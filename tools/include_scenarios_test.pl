/* include_scenarios_test.pl — scenarios from another file, in an LPS document.

   `the knowledge base <name> includes these scenarios: <file>, ...` is read
   by LE2 (docs/user/reference/le-for-lps.md §1.2). What LPS2 has to hold is
   that a scenario from such a file is a scenario like the document's own:

   - `lps run --scenario NAME` runs it, and a name the document does not have
     is refused with every name, the included ones among them;
   - without a choice the run takes the document's own first scenario;
   - an `initially` sentence of a scenario file is kept, because it
     describes the case (the opposite of `extends`, §1.1);
   - the IDE's analysis lists the included scenarios, for the picker beside
     Run, after the document's own.

   examples/le/transfer.le, transfer_cases.le and transfer_rules.le are the
   example. Needs an LE2 checkout:

     LPS_LE2_LIB=/LogicalEnglish2 ./myswipl.sh -q -g "consult('tools/include_scenarios_test.pl')" -g "incsc:main" -t halt
*/

:- module(incsc, [main/0]).

:- use_module('../src/edges/lps_le').
:- use_module('../src/edges/lps_api').
:- use_module(library(lists)).

:- dynamic failures/1.
failures(0).

main :-
	(   lps_le_available(lib(_))
	->  retractall(failures(_)), assertz(failures(0)),
	    forall(test(Name, Goal), run_test(Name, Goal)),
	    failures(N),
	    (   N =:= 0
	    ->  format('include scenarios: all tests pass~n', [])
	    ;   format('include scenarios: ~w FAILED~n', [N]), halt(1)
	    )
	;   format('include scenarios: skipped (set LPS_LE2_LIB to an LE2 checkout)~n', [])
	).

run_test(Name, Goal) :-
	(   catch(Goal, E, (print_message(error, E), fail))
	->  format('  ok    ~w~n', [Name])
	;   format('  FAIL  ~w~n', [Name]),
	    retract(failures(N0)), N is N0 + 1, assertz(failures(N))
	).

test('an included scenario is run by name', (
	translate(small, Text, Diags),
	sub_string(Text, _, _, _, "observe([transfer(fariba,10,bob)],2)"),
	\+ sub_string(Text, _, _, _, "transfer(fariba,50,bob)"),
	\+ member(diag(error, _, _, _, _), Diags) )).

test('without a choice, the document\'s own scenario is run', (
	translate(none, Text, Diags),
	sub_string(Text, _, _, _, "observe([transfer(fariba,50,bob)],2)"),
	member(diag(warning, lps_several_scenarios, _, M, _), Diags),
	sub_atom(M, _, _, _, 'large, small, overdrawn') )).

test('an unknown name is refused with the included names', (
	translate(nope, _, Diags),
	member(diag(error, lps_no_such_scenario, _, M, _), Diags),
	sub_atom(M, _, _, _, overdrawn) )).

test('the program runs the included scenario', (
	run_lps(['run', 'examples/le/transfer.le', '--scenario', 'overdrawn'], Status, Output),
	Status == exit(0),
	%  bob has nothing, so the constraint refuses his transfer
	\+ sub_string(Output, _, _, _, "transfer(bob,5,fariba)"),
	sub_string(Output, _, _, _, "balance(bob,0)") )).

test('an initially sentence of a scenario file is kept', (
	with_files([ 'rules.le'-rules_text, 'cases.le'-cases_text, 'main.le'-main_text ],
		   [Dir]>>( directory_file_path(Dir, 'main.le', Main),
			    lps_le_with_scenario(two, lps_le_translate(Main, Text, _, _)),
			    sub_string(Text, _, _, _, "initial_state([balance(carol,5)])"),
			    sub_string(Text, _, _, _, "observe([transfer(carol,5,dan)],2)") )) )).

test('the analysis lists the included scenarios after the document\'s own', (
	analysed_scenarios(Ps),
	Ps = ["large"-L1, "small"-0, "overdrawn"-0],
	L1 > 0 )).

%	The scenario blocks of the IDE's analysis of transfer.le, as Name-Line.
analysed_scenarios(Ps) :-
	root(Root),
	atomic_list_concat([Root, '/examples/le/transfer.le'], File),
	read_file_to_string(File, Source, []),
	lps_api:operation("le_analyse", _{source: Source, name: "transfer.le"}, R),
	get_dict(blocks, R, Blocks),
	findall(N-L, ( member(B, Blocks), get_dict(kind, B, "scenario"),
		       get_dict(name, B, N), get_dict(line, B, L) ), Ps).

translate(Scenario, Text, Diags) :-
	root(Root),
	atomic_list_concat([Root, '/examples/le/transfer.le'], File),
	(   Scenario == none
	->  lps_le_translate(File, Text, _, Diags)
	;   lps_le_with_scenario(Scenario, lps_le_translate(File, Text, _, Diags))
	).

run_lps(Args, Status, Output) :-
	root(Root),
	atomic_list_concat([Root, '/lps'], Lps),
	process_create(Lps, Args, [cwd(Root), stdout(pipe(Out)), stderr(null), process(P)]),
	read_string(Out, _, Output),
	close(Out),
	process_wait(P, Status).

rules_text("the target language is: lps.

the maximum time is 3.

the actions are:
    *a payer* transfers *an amount* to *a payee*; known as transfer.

the fluents are:
    the balance of *a person* is *an amount*; known as balance.

the knowledge base rules includes:

when a payer transfers an amount to a payee
then the balance of the payee that is a number becomes number + amount
    and the balance of the payer that is a second number becomes second number - amount.
").

cases_text("the target language is: lps.

the knowledge base cases includes these resources:
    rules.

the knowledge base cases includes:

initially the balance of carol is 5.

scenario two is:
    carol transfers 5 to dan from 1 to 2.
").

main_text("the target language is: lps.

the knowledge base main includes these resources:
    rules.

the knowledge base main includes these scenarios:
    cases.

the knowledge base main includes:

initially the balance of dan is 0.

scenario one is:
    dan transfers 0 to carol from 1 to 2.
").

with_files(Files, Goal) :-
	tmp_file(incsc, Dir),
	make_directory(Dir),
	forall(member(F-P, Files),
	       ( directory_file_path(Dir, F, Path), call(P, T),
		 setup_call_cleanup(open(Path, write, S), write(S, T), close(S)) )),
	setup_call_cleanup(true, call(Goal, Dir), delete_directory_and_contents(Dir)).

root(Root) :-
	module_property(incsc, file(F)),
	file_directory_name(F, Tools),
	file_directory_name(Tools, Root).

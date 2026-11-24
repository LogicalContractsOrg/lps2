/* solidity_test.pl — the gate for LPS2's Misc ▸ Deploy as Solidity.

   src/syntax/lps_solidity.pl writes an LPS program as a Solidity contract,
   or refuses with the reasons. This gate loads it through
   src/syntax/lps_plus.pl, as the IDE and the command line do.

   This gate checks both halves:

   1. **Refusals.** Small programs, each with one feature that has no straight
      translation (a reactive rule, a fraction, an enumeration, an event of the
      environment, planning), must be refused with that feature's code — and a
      small compatible program written in LPS syntax must not be.

   2. **The corpus translates, compiles and behaves.** The Solidity twins in
      examples/migration/solidity (OpenZeppelin ERC-20,
      Ownable, Pausable, their Wizard composition, Circle's FiatToken —
      Logical English for LPS, read from deployed Solidity by Logical
      English's Solidity reader, migration/solidity/ in LE2) are written back as
      Solidity; each must compile with solc with no warning; and, on an
      in-process EVM, the program's own scenario replayed as calls must leave
      the contract in the state LPS2's run of the program ends in — every fact
      of LPS2's final state read back through the contract's getters, and every
      absent key (over the names the scenario mentions) absent there too. The
      same refusals LPS2 makes (a constraint violated) are the EVM's reverts.

	LPS_LE2_LIB=<an LE2 checkout> ./myswipl.sh -q -g "consult('tools/solidity_test.pl')" -g "solt:main" -t halt

   The corpus needs LE2 (LPS_LE2_LIB) and the twins
   (examples/migration/solidity, or LPS_SOLIDITY_TWINS); solc and the EVM
   come from build/evm/node_modules, this checkout's gitignored scratch
   (`npm i --prefix build/evm solc@0.8.26 @ethereumjs/vm@10
   @ethereumjs/common@10 @ethereumjs/util@10`), or from LPS_SOLC_MODULES and
   LPS_EVM_MODULES; without a solc there, the one in LE2's
   migration/solidity/node_modules is used. What is missing is skipped and
   said so, never counted as a pass.
*/

:- module(solt, [main/0]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.

%  The LPS2 this gate belongs to: the parent of tools/.
:- dynamic lps2_root/1.
:- prolog_load_context(directory, Dir), file_directory_name(Dir, Root),
   retractall(lps2_root(_)), assertz(lps2_root(Root)).
lps2_dir(L) :- lps2_root(L).

:- use_module('../src/core/lps_diag').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_program').
:- use_module('../src/syntax/lps_plus').
:- use_module('../src/edges/lps_le').
:- use_module('../src/edges/lps_cli', []).
:- use_module('../src/edges/lps_source').
%  The call plan, the EVM harness and the size limits are shared with the
%  cost report (lps_solidity_cost.pl), so that a figure this gate checks and a
%  figure `lps solidity --cost` prints can never come from different calls.
:- use_module('../src/syntax/lps_solidity_cost').

:- dynamic result/2.

main :-
	retractall(result(_, _)),
	forall(refusal_case(Name, Src, Code), refusal(Name, Src, Code)),
	refusal_located,
	compatible_lps,
	corpus,
	cost_measured,
	cost_refuses_oversize,
	budget_met,
	budget_near_warns,
	budget_broken,
	overflow_noted,
	overflow_bound_dropped,
	overflow_bound_runs,
	findall(N, result(N, pass), Ps), length(Ps, P),
	findall(N-R, ( result(N, R), R \== pass, R \= skip(_) ), Fs), length(Fs, F),
	findall(N-W, result(N, skip(W)), Ss), length(Ss, S),
	forall(member(N-R, Fs), format('FAIL ~w: ~w~n', [N, R])),
	forall(member(N-W, Ss), format('skip ~w: ~w~n', [N, W])),
	format('~n=== solidity: ~w passed, ~w failed, ~w skipped ===~n', [P, F, S]),
	( F =:= 0 -> true ; halt(1) ).

record(N, R) :- assertz(result(N, R)), format('~w: ~q~n', [N, R]).

		 /*******************************
		 *	      refusals		*
		 *******************************/

%	A program in LPS syntax, compiled and refused with Code.
refusal_case(reactive_rule, "fluents f. actions a. if true then a from T1 to T2.", reactive_rule).
refusal_case(fraction, "fluents v(_). actions halve(_). initially v(10). halve(X) updates Old to New in v(Old) if New is Old / 2.", non_integer).
refusal_case(enumeration, "fluents member(_). actions join(_), wipe(_). join(X) initiates member(X). wipe(_) terminates member(Y) if member(Y).", enumeration).
refusal_case(environment_event, "fluents raining. events rain. rain initiates raining. observe rain from 1 to 2.", environment_event).
refusal_case(two_values, "fluents rate(_). actions set(_,_), bump(_). initially rate(1). set(_, R) initiates rate(R). bump(_) updates Old to New in rate(Old) if New is Old + 1.", two_values).
refusal_case(not_lps, "happy(alice). sad(X) :- \\+ happy(X).", not_lps).
refusal_case(planning, ":- lps_engine(planning, []). fluents at(_). actions go(_). go(X) initiates at(X). achieve at(home).", planning).

refusal(Name, Src, Code) :-
	(   compile_text(Src, P)
	->  lps_solidity:lps_to_solidity(P, [origin('t.lps')], R),
	    (   R = refused(Ds), member(D, Ds), diag_code(D, Code)
	    ->  record(refuses(Name), pass)
	    ;   R = refused(Ds)
	    ->  maplist(diag_code, Ds, Cs), record(refuses(Name), wrong_codes(Cs))
	    ;   record(refuses(Name), not_refused)
	    )
	;   record(refuses(Name), did_not_compile)
	).

%	A refusal says where, in the document's terms: the clause's line of an
%	LPS document under the document's name (not `buffer`, the compiler's
%	name for text), and no line at all for a Logical English document whose
%	LPS reading has the clause (the reading's lines are not the document's).
refusal_located :-
	Src = "fluents raining. events rain. rain initiates raining.\nobserve rain from 1 to 2.",
	(   compile_text(Src, P)
	->  lps_solidity:lps_to_solidity(P, [origin('rain.lps')], R1),
	    lps_solidity:lps_to_solidity(P, [origin('rain.le')], R2),
	    (   R1 = refused(D1s), member(D1, D1s), diag_code(D1, environment_event), diag_position(D1, src('rain.lps', 2, _, _)),
		R2 = refused(D2s), member(D2, D2s), diag_code(D2, environment_event), diag_position(D2, unknown),
		\+ ( member(D, D1s), diag_position(D, src(buffer, _, _, _)) )
	    ->  record(refusal_located, pass)
	    ;   record(refusal_located, wrong_positions(R1, R2))
	    )
	;   record(refusal_located, did_not_compile)
	).

compile_text(Src, P) :-
	lps_source:lps_read_terms_string(Src, buffer, Raw, D1), diags_ok(D1),
	lps_compile(terms(Raw), legacy, [dc], P, Diags),
	P \== none, diags_ok(Diags).

%	A small bank in LPS syntax: no templates, no LE — names come from types.
compatible_lps :-
	Src = "fluents balance(_, _), frozen(_).
actions deposit(_, _), withdraw(_, _), freeze(_), transfer(_, _, _).
initially balance(bank, 100).
deposit(A, N) initiates balance(A, 0) if not balance(A, _).
deposit(A, N) updates Old to New in balance(A, Old) if New is Old + N.
withdraw(A, N) updates Old to New in balance(A, Old) if New is Old - N.
false withdraw(A, N), balance(A, B), B < N.
false withdraw(A, N), not balance(A, _).
false withdraw(A, _), frozen(A).
false withdraw(A, N), not vip(A), N > 25.
vip(alice).
vip(bank).
freeze(A) initiates frozen(A).
observe deposit(alice, 50) from 1 to 2.
observe withdraw(alice, 20) from 2 to 3.
observe freeze(alice) from 3 to 4.
observe withdraw(alice, 10) from 4 to 5.
observe withdraw(bank, 500) from 5 to 6.
observe deposit(carol, 100) from 6 to 7.
observe withdraw(carol, 40) from 7 to 8.
observe withdraw(carol, 25) from 8 to 9.",
	(   compile_text(Src, P)
	->  check_program(bank_lps, P, [origin('bank.lps')])
	;   record(bank_lps, did_not_compile)
	).

		 /*******************************
		 *	     the corpus		*
		 *******************************/

twin_root(R) :-
	(   getenv('LPS_SOLIDITY_TWINS', R0) -> R = R0
	;   lps2_dir(L), atomic_list_concat([L, '/examples/migration/solidity'], R)
	).
twin(erc20). twin(ownable). twin(pausable). twin(mytoken). twin(fiat_token).

corpus :-
	twin_root(Root),
	(   \+ exists_directory(Root)
	->  record(corpus, skip('no Solidity twins (LPS_SOLIDITY_TWINS)'))
	;   \+ lps_le_available(lib(_))
	->  record(corpus, skip('LE2 not loaded (LPS_LE2_LIB)'))
	;   forall(twin(T), corpus_case(Root, T)),
	    negative_control(Root)
	).

%	The replay has to be able to fail: the ERC-20 contract with one debit
%	turned into a credit must disagree with LPS2.
negative_control(Root) :-
	format(atom(F), '~w/erc20/erc20.le', [Root]),
	(   exists_file(F),
	    lps_cli:compile_source(le, F, [], P, _), P \== none
	->  read_file_to_string(F, Text, []),
	    lps_le_templates(Text, F, Ts),
	    lps_solidity:lps_to_solidity(P, [interface(I), templates(Ts), source(Text), origin(F)], solidity(Sol0, C, _)),
	    atomic_list_concat(Parts, ' - amount)', Sol0),
	    Parts = [First|Rest], Rest \== [],
	    atomic_list_concat(Rest, ' - amount)', RestS),
	    atomic_list_concat([First, ' + amount)', RestS], Sol),
	    lps_final_state(P, Final),
	    plan(P, I, Sol, C, Final, Plan, Expect),
	    run_evm(Plan, Out),
	    (   is_dict(Out), Out.get(deployed) == true
	    ->  findall(x, ( nth1(K, Expect, X), nth1(K, Out.reads, G), \+ same_value(X, G) ), Bad),
		length(Bad, NB),
		( NB > 0 -> record(negative_control, pass), format('    the mutant disagrees on ~w values~n', [NB])
		; record(negative_control, mutant_agrees) )
	    ;   record(negative_control, skip('no EVM'))
	    )
	;   record(negative_control, skip(missing))
	).

corpus_case(Root, T) :-
	format(atom(F), '~w/~w/~w.le', [Root, T, T]),
	(   exists_file(F)
	->  catch(( lps_cli:compile_source(le, F, [], P, Diags), P \== none, diags_ok(Diags) ), _, fail)
	->  read_file_to_string(F, Text, []),
	    lps_le_templates(Text, F, Ts),
	    check_program(T, P, [templates(Ts), source(Text), origin(F)])
	;   record(T, did_not_compile)
	;   record(T, skip(missing))
	).

		 /*******************************
		 *	    what it costs	*
		 *******************************/

%	`cost(true)` measures the contract rather than estimating it
%	(the design notes on language coverage, §2.1.5 E1), so what this
%	checks is that the measurement happened and is of the right order — not
%	the exact figures, which move with the solc version and the fork. The
%	20% band is wide enough for a compiler upgrade and narrow enough that a
%	contract that has doubled in size fails here.
cost_expectation(erc20, deployed, 2759).
cost_expectation(erc20, deploy_gas, 686243).
cost_expectation(erc20, first_call, 49570).      % alice: transfer(bob, 300), with intrinsic

cost_measured :-
	twin_root(Root), format(atom(F), '~w/erc20/erc20.le', [Root]),
	(   \+ exists_file(F) -> record(cost, skip('no Solidity twins'))
	;   \+ lps_le_available(lib(_)) -> record(cost, skip('LE2 not loaded (LPS_LE2_LIB)'))
	;   catch(( lps_cli:compile_source(le, F, [], P, _), P \== none ), _, fail)
	->  read_file_to_string(F, Text, []),
	    lps_le_templates(Text, F, Ts),
	    lps_solidity:lps_to_solidity(P, [interface(I), templates(Ts), source(Text), origin(F)],
					 solidity(Sol, C, _)),
	    solidity_cost(P, Sol, C, I, [], Report),
	    (   Report = not_measured(W) -> record(cost, skip(W))
	    ;   Report = measured(D)
	    ->  cost_checks(D)
	    )
	;   record(cost, did_not_compile)
	).

cost_checks(D) :-
	%  every figure is of a stated fork and compiler: without those the
	%  numbers mean nothing, so their absence is a failure, not a note
	(   get_dict(fork, D, Fork), Fork \== null, get_dict(solc, D, Solc), Solc \== null
	->  record(cost_provenance, pass)
	;   record(cost_provenance, no_fork_or_solc)
	),
	(   get_dict(size, D, Sz), get_dict(deployed, Sz, Dep),
	    code_size_limit(deployed, Limit), Dep < Limit,
	    near(erc20, deployed, Dep)
	->  record(cost_size, pass)
	;   record(cost_size, unexpected(D.size))
	),
	(   get_dict(deployGas, D, GS), number_string(G, GS), near(erc20, deploy_gas, G)
	->  record(cost_deploy_gas, pass)
	;   record(cost_deploy_gas, unexpected(D.deployGas))
	),
	%  the scenario's first call, with the intrinsic a sender also pays
	(   get_dict(calls, D, [R1|_]), get_dict(total, R1, T1), near(erc20, first_call, T1),
	    get_dict(intrinsic, R1, In1), In1 > 21000, get_dict(ok, R1, true)
	->  record(cost_call_gas, pass)
	;   record(cost_call_gas, unexpected(D.calls))
	),
	%  a call the program's constraints refuse is a revert on chain, and is
	%  reported as one: the sender still pays the intrinsic
	(   get_dict(calls, D, Rs), member(R, Rs), get_dict(ok, R, false),
	    get_dict(intrinsic, R, In), In > 21000
	->  record(cost_revert_reported, pass)
	;   record(cost_revert_reported, no_reverted_call)
	).

near(Name, Which, V) :-
	cost_expectation(Name, Which, E),
	V >= E * 0.8, V =< E * 1.2.

%	A contract over EIP-170 is not a contract: the exporter must refuse it
%	rather than hand over source that no chain will take. Fifty independent
%	accounts' worth of functions is about 26 kB of deployed bytecode —
%	nothing exotic, which is the point: an author can reach this by writing
%	an ordinary program that is merely large.
cost_refuses_oversize :-
	oversize_source(50, Src),
	(   compile_text(Src, P)
	->  lps_solidity:lps_to_solidity(P, [cost(true), origin('big.lps')], R),
	    (   R = refused(Ds), member(D, Ds), diag_code(D, code_size), diag_severity(D, error)
	    ->  record(cost_refuses_oversize, pass)
	    ;   R = refused(Ds)
	    ->  maplist(diag_code, Ds, Cs), record(cost_refuses_oversize, wrong_codes(Cs))
	    ;   R = solidity(_, _, Ns), member(N, Ns), diag_code(N, cost_not_measured)
	    ->  record(cost_refuses_oversize, skip('the cost was not measured here'))
	    ;   record(cost_refuses_oversize, not_refused)
	    )
	;   record(cost_refuses_oversize, did_not_compile)
	).

oversize_source(N, Src) :-
	numlist(1, N, Is),
	findall(S, ( member(I, Is), format(atom(S),
"fluents balance~w(_, _).
actions deposit~w(_, _), withdraw~w(_, _).
initially balance~w(bank, 100).
deposit~w(A, M) initiates balance~w(A, 0) if not balance~w(A, _).
deposit~w(A, M) updates Old to New in balance~w(A, Old) if New is Old + M.
withdraw~w(A, M) updates Old to New in balance~w(A, Old) if New is Old - M.
false withdraw~w(A, M), balance~w(A, B), B < M.
", [I,I,I,I,I,I,I,I,I,I,I,I,I]) ), Ss),
	atomic_list_concat(Ss, Src0), atom_string(Src0, Src).

		 /*******************************
		 *	  stated budgets	*
		 *******************************/

%	A check whose program is a Logical English document needs LE2 in this
%	process (LPS_LE2_LIB). Without it the check is skipped and said so:
%	it is not counted as a pass, and not as a failure of the translator.
without_le(Name) :-
	\+ lps_le_available(lib(_)),
	record(Name, skip('LE2 not loaded (LPS_LE2_LIB)')).

%	E2: the budget an author states, in the language, checked against the
%	measurement (§2.1.5). The same program twice — the second with a gas
%	budget the measured call breaks — must emit unchanged and then refuse,
%	and the refusal must carry the figure: a budget whose breach you cannot
%	see is a budget you cannot act on.
%
%	The measured call is about 49,500 gas in all: 80,000 is comfortably met,
%	55,000 is met but within the 20% band decision 4 asks to be warned
%	about, and 30,000 is broken — each far enough from the figure to survive
%	a compiler that moves it.
%
%	*Emits unchanged* is checked literally: the contract written with the
%	budget sentence must be the same text as the one written without it. A
%	budget is a thing said about the contract, and must not be a thing that
%	changes it.
budget_met :- without_le(budget_met), !.
budget_met :-
	budget_case(80000, R),
	budget_case(none, R0),
	(   R = solidity(_, _, Ns), member(N, Ns), diag_code(N, budget_within)
	->  (   R0 = solidity(Plain, _, _), R = solidity(Plain, _, _)
	    ->  record(budget_met, pass)
	    ;   record(budget_met, changed_the_contract)
	    )
	;   R = solidity(_, _, Ns), nothing_measured(Ns)
	->  record(budget_met, skip('the cost was not measured here'))
	;   R = solidity(_, _, _)
	->  record(budget_met, budget_not_reported)
	;   R = refused(Ds), maplist(format_diag, Ds, Ms), record(budget_met, refused(Ms))
	;   record(budget_met, R)
	).

%	Decision 4: a call within 20% of its budget is a warning, not a note —
%	and it is not a refusal either, so the contract is still written.
budget_near_warns :- without_le(budget_near_warns), !.
budget_near_warns :-
	budget_case(55000, R),
	(   R = solidity(_, _, Ns), member(N, Ns), diag_code(N, budget_near), diag_severity(N, warning)
	->  record(budget_near_warns, pass)
	;   R = solidity(_, _, Ns), nothing_measured(Ns)
	->  record(budget_near_warns, skip('the cost was not measured here'))
	;   R = solidity(_, _, Ns), maplist(diag_code, Ns, Cs), record(budget_near_warns, no_warning(Cs))
	;   record(budget_near_warns, refused)
	).

budget_broken :- without_le(budget_broken), !.
budget_broken :-
	budget_case(30000, R),
	(   R = refused(Ds), member(D, Ds), diag_code(D, budget_breach), diag_severity(D, error),
	    diag_message(D, M), sub_atom(M, _, _, _, '30000'), figure_in(M)
	->  record(budget_broken, pass)
	;   R = refused(Ds), member(D, Ds), diag_code(D, budget_breach)
	->  diag_message(D, M), record(budget_broken, no_figure(M))
	;   R = solidity(_, _, Ns), nothing_measured(Ns)
	->  record(budget_broken, skip('the cost was not measured here'))
	;   record(budget_broken, not_refused)
	).

%	The message must name what was measured, not only what was allowed.
figure_in(M) :-
	atom_string(M, S), split_string(S, " ,", " ,.", Ws),
	member(W, Ws), number_string(N, W), N > 30000.

%	No node, no solc, or no EVM: the report says so, and a budget nothing
%	measured says so too. Either way there is nothing for these cases to
%	check, and a skip is the honest result.
nothing_measured(Notes) :-
	member(N, Notes), diag_code(N, C),
	memberchk(C, [cost_not_measured, budget_unchecked]), !.

budget_case(Limit, R) :-
	budget_le(Limit, Text),
	setup_call_cleanup(
	    tmp_file_stream(text, File, Out),
	    ( write(Out, Text), close(Out),
	      (   catch(( lps_cli:compile_source(le, File, [], P, _), P \== none ), _, fail)
	      ->  lps_le_templates(Text, File, Ts),
		  %  a stable origin: the contract's header names the document it
		  %  came from, and two runs of this case must differ only where
		  %  the budget sentence makes them differ
		  lps_solidity:lps_to_solidity(P, [templates(Ts), source(Text), origin('budget.le')], R)
	      ;   R = did_not_compile
	      )
	    ),
	    delete_file(File)).

budget_le(Limit, Text) :-
	budget_sentence(Limit, Sentence),
	format(atom(Text),
"the target language is: lps.

the maximum time is 4.

the actions are:
    *a sender* pays *an amount* to *a recipient*; known as pay.

the fluents are:
    the balance of *an account* is *an amount*; known as balance; 0 by default.

the knowledge base budgets includes:

initially the balance of alice is 100.

it must not be true that
    a sender pays an amount to a recipient
    and the balance of the sender is a second amount
    and the second amount < the amount.

when a sender pays an amount to a recipient
then the balance of the sender that is a second amount becomes second amount - amount.

when a sender pays an amount to a recipient
then the balance of the recipient that is a second amount becomes second amount + amount.

~w
scenario one is:
    alice pays 30 to bob from 1 to 2.
", [Sentence]).

budget_sentence(none, '') :- !.
budget_sentence(Limit, S) :-
	format(atom(S),
"it must not be true that
    the gas of pay is an amount
    and the amount > ~w.
", [Limit]).

		 /*******************************
		 *   arithmetic that can revert	*
		 *******************************/

%	E3.1: what the contract refuses and the program does not. The ERC-20
%	twin is the case worth pinning, because it has both kinds — every debit
%	is bounded by the constraint that reverts with ERC20InsufficientBalance,
%	and no credit is bounded by anything, which is exactly what OpenZeppelin
%	relies on the total supply for and never says in the code.
overflow_noted :-
	twin_root(Root), format(atom(F), '~w/erc20/erc20.le', [Root]),
	(   \+ exists_file(F) -> record(overflow_noted, skip('no Solidity twins'))
	;   \+ lps_le_available(lib(_)) -> record(overflow_noted, skip('LE2 not loaded'))
	;   catch(( lps_cli:compile_source(le, F, [], P, _), P \== none ), _, fail)
	->  read_file_to_string(F, Text, []),
	    lps_le_templates(Text, F, Ts),
	    lps_solidity:lps_to_solidity(P, [templates(Ts), source(Text), origin(F)], R),
	    (   R = solidity(_, _, Ns),
		findall(M, ( member(N, Ns), diag_code(N, unbounded_arithmetic), diag_message(N, M) ), Ms),
		Ms \== [],
		forall(member(M, Ms), sub_atom(M, _, _, _, 'an addition')),
		%  the debits are bounded, and must not be listed
		\+ ( member(M, Ms), sub_atom(M, _, _, _, 'subtraction') )
	    ->  length(Ms, NM), record(overflow_noted, pass),
		format('    ~w unbounded additions, no unbounded subtraction~n', [NM])
	    ;   R = solidity(_, _, Ns)
	    ->  findall(C, ( member(N, Ns), diag_code(N, C) ), Cs), record(overflow_noted, wrong_notes(Cs))
	    ;   record(overflow_noted, refused)
	    )
	;   record(overflow_noted, did_not_compile)
	).

%	E3.2: the program says the bound Solidity enforces anyway. The
%	constraint must then be recognised — the site is no longer listed as
%	unbounded — and must **not** be written a second time as a revert in
%	front of the checked `+`.
overflow_bound_dropped :- without_le(overflow_bound_dropped), !.
overflow_bound_dropped :-
	overflow_case(R),
	(   R = solidity(Sol, _, Ns)
	->  (   member(N, Ns), diag_code(N, bound_already_checked),
		\+ ( member(N2, Ns), diag_code(N2, unbounded_arithmetic) ),
		%  `revert ` with the space is the statement; the contract's own
		%  header explains that constraints *are* reverts, and says so
		%  in every contract
		\+ sub_atom(Sol, _, _, _, 'revert ')
	    ->  record(overflow_bound_dropped, pass)
	    ;   findall(C, ( member(N, Ns), diag_code(N, C) ), Cs),
		record(overflow_bound_dropped, wrong(Cs))
	    )
	;   R = refused(Ds), maplist(format_diag, Ds, Ms), record(overflow_bound_dropped, refused(Ms))
	;   record(overflow_bound_dropped, R)
	).

%	And the other half of E3.2, which is the reason to write the sentence at
%	all: a run of the program now refuses the call the chain would revert.
overflow_bound_runs :- without_le(overflow_bound_runs), !.
overflow_bound_runs :-
	overflow_le(Max, Text),
	Over is Max + 1,
	(   catch(( lps_source:lps_read_terms_string("", buffer, _, _) ), _, fail) -> true ; true ),
	(   compile_le_text(Text, P)
	->  lps_final_state(P, Final),
	    (   memberchk(balance(alice, Max), Final)
	    ->  record(overflow_bound_runs, pass)
	    ;   memberchk(balance(alice, Over), Final)
	    ->  record(overflow_bound_runs, overflowed)
	    ;   record(overflow_bound_runs, unexpected(Final))
	    )
	;   record(overflow_bound_runs, did_not_compile)
	).

overflow_case(R) :-
	overflow_le(_, Text),
	(   compile_le_text(Text, P)
	->  lps_solidity:lps_to_solidity(P, [source(Text), origin('overflow.le')], R)
	;   R = did_not_compile
	).

compile_le_text(Text, P) :-
	setup_call_cleanup(
	    tmp_file_stream(text, File, Out),
	    ( write(Out, Text), close(Out),
	      catch(( lps_cli:compile_source(le, File, [], P, _), P \== none ), _, fail) ),
	    delete_file(File)).

%	The balance starts at the largest whole number, and the scenario adds
%	one to it: the contract's checked `+` would revert, and the program's
%	own constraint must refuse the call for the same reason.
overflow_le(115792089237316195423570985008687907853269984665640564039457584007913129639935, Text) :-
	Text =
"the target language is: lps.

the maximum time is 4.

the actions are:
    *a depositor* deposits *an amount*; known as deposit.

the fluents are:
    the balance of *an account* is *an amount*; known as balance; 0 by default.

the knowledge base overflow includes:

initially the balance of alice is 115792089237316195423570985008687907853269984665640564039457584007913129639935.

it must not be true that
    a depositor deposits an amount
    and the balance of the depositor is a second amount
    and the largest whole number is a third amount
    and second amount + amount > the third amount.

when a depositor deposits an amount
then the balance of the depositor that is a second amount becomes second amount + amount.

scenario one is:
    alice deposits 1 from 1 to 2.
".

		 /*******************************
		 *   generate, compile, replay	*
		 *******************************/

check_program(Name, P, Opts) :-
	lps_solidity:lps_to_solidity(P, [interface(I)|Opts], R),
	(   R = solidity(Sol, Contract, _)
	->  record(generates(Name), pass),
	    lps_final_state(P, Final),
	    plan(P, I, Sol, Contract, Final, Plan, Expect),
	    run_evm(Plan, Out),
	    judge(Name, Out, Expect)
	;   R = refused(Ds)
	->  maplist(format_diag, Ds, Ms), record(generates(Name), refused(Ms))
	).

lps_final_state(P, Fluents) :-
	lps_session_new(P, [dc], S0),
	lps_session_run(S0, end, S, _),
	lps_session_state(S, Fluents).

%	The plan the EVM runs, and what each read is expected to return
%	(Expect: one per read, in order).
plan(P, I, Sol, Contract, Final, Plan, Expect) :-
	I = iface(Acts, Fls, Ctor),
	solidity_call_plan(P, I, Calls, CtorT),
	findall(T-E, ( p_observe(P, Es, T), member(E, Es) ), TEs0), msort(TEs0, TEs),
	names_seen(Acts, Fls, TEs, Final, Ctor, Names),
	findall(Rd-X, ( member(Fl, Fls), fluent_reads(Fl, Final, Names, Rd, X) ), RXs),
	pairs_keys_values(RXs, Reads, Expect),
	Plan = _{source: Sol, contract: Contract, ctor: CtorT, calls: Calls, reads: Reads}.

%	The address names: everything the scenario, the constructor and the final
%	state put in an address position.
names_seen(Acts, Fls, TEs, Final, Ctor, Names) :-
	findall(V, ( member(_-E, TEs), functor(E, A, N), memberchk(act(A/N, _, _, Ts), Acts),
		     E =.. [_|Vs], nth1(I, Vs, V), nth1(I, Ts, address) ), N1),
	findall(V, ( member(Fl, Final), functor(Fl, F, N), memberchk(fl(F/N, _, _, _, _, Ts), Fls),
		     Fl =.. [_|Vs], nth1(I, Vs, V), nth1(I, Ts, address) ), N2),
	append([N1, N2, Ctor], Names0), sort(Names0, Names).

%	Reads for one fluent: presence and value of every key tuple (over the
%	names seen, and the tuples of the final state), membership for a set.
fluent_reads(fl(F/0, bool, _, G, _, _), Final, _, _{fn: G, args: [], out: bool}, X) :- !,
	( memberchk(F, Final) -> X = true ; X = false ).
fluent_reads(fl(F/N, Shape, VP, G, H, Ts), Final, Names, Read, X) :-
	(   Shape == functional -> nth1(VP, Ts, _, KTs) ; KTs = Ts ),
	key_tuples(F/N, Shape, VP, KTs, Final, Names, Tuples),
	member(Keys, Tuples),
	maplist(arg_json, KTs, Keys, KArgs),
	(   Shape == set
	->  Fl =.. [F|Keys],
	    Read = _{fn: G, args: KArgs, out: bool},
	    ( memberchk(Fl, Final) -> X = true ; X = false )
	;   nth1(VP, Ts, VT),
	    key_value_of(F/N, VP, Keys, Final, V),
	    (   H = default(D)
	    ->  %  no presence map: an absent key reads as its default
		( V == none -> V1 = D ; V1 = V ),
		Read = _{fn: G, args: KArgs, out: VT}, value_text(VT, V1, X)
	    ;   V == none
	    ->  Read = _{fn: H, args: KArgs, out: bool}, X = false
	    ;   ( Read = _{fn: H, args: KArgs, out: bool}, X = true
		; Read = _{fn: G, args: KArgs, out: VT}, value_text(VT, V, X0), ( VT == bool -> X = X0 ; X = X0 ) )
	    )
	).

key_tuples(F/N, Shape, VP, KTs, Final, Names, Tuples) :-
	findall(Keys, ( member(Fl, Final), functor(Fl, F, N), Fl =.. [_|Vs],
			( Shape == functional -> nth1(VP, Vs, _, Keys) ; Keys = Vs ) ), T1),
	(   forall(member(T, KTs), T == address), length(KTs, K), K =< 2
	->  findall(Keys, ( length(Keys, K), maplist(member_of(Names), Keys) ), T2)
	;   T2 = []
	),
	append(T1, T2, T0), sort(T0, Tuples).

member_of(L, X) :- member(X, L).

key_value_of(F/N, VP, Keys, Final, V) :-
	(   member(Fl, Final), functor(Fl, F, N), Fl =.. [_|Vs], nth1(VP, Vs, V0, Keys0), Keys0 == Keys
	->  V = V0
	;   V = none
	).

%	The EVM harness is lps_solidity_cost:run_evm_plan/2 — the same child
%	process, the same script, the same way of finding its modules, so that
%	a replay and a cost report cannot disagree about what was run. The only
%	difference is what this gate does with a missing solc.
run_evm(Plan, Out) :-
	run_evm_plan(Plan, Out0),
	( Out0 = skip(_) -> Out = skip('solc not found') ; Out = Out0 ).

judge(Name, skip(W), _) :- !, record(compiles(Name), skip(W)).
judge(Name, error(E), _) :- !, record(compiles(Name), error(E)).
judge(Name, Out, Expect) :-
	(   Out.get(compiled) == true
	->  (   Out.get(warnings) == []
	    ->  record(compiles(Name), pass)
	    ;   record(compiles(Name), warnings(Out.warnings))
	    ),
	    (   Out.get(deployed) == null
	    ->  record(replays(Name), skip('no EVM (build/evm or LPS_EVM_MODULES)'))
	    ;   Out.get(deployed) == true
	    ->  Reads = Out.reads,
		findall(I-X-G, ( nth1(I, Expect, X), nth1(I, Reads, G), \+ same_value(X, G) ), Bad),
		length(Expect, NE),
		(   Bad == []
		->  record(replays(Name), pass), format('    ~w values agree with LPS2~n', [NE])
		;   length(Bad, NB), Bad = [B1|_],
		    record(replays(Name), disagree(NB, of(NE), first(B1)))
		)
	    ;   record(replays(Name), not_deployed(Out))
	    )
	;   record(compiles(Name), errors(Out.get(errors)))
	).

same_value(X, G) :- X == G, !.
same_value(X, G) :- string(X), string(G), X == G, !.
same_value(X, G) :- ( atom(X) ; string(X) ), ( atom(G) ; string(G) ), atom_string(A, X), atom_string(A, G).

/* lps_solidity_cost.pl — what the contract this program just became will cost.

   *Deploy as Solidity* writes a contract; this measures the one it wrote.
   Two questions an author cannot answer from the text, and both have exact
   answers available for the asking:

     will it deploy?   EIP-170 caps a contract's deployed bytecode at 24,576
		       bytes and EIP-3860 its initcode at 49,152. Above either,
		       there is no contract — so those are refusals, not notes.
     what will it cost? the gas of each call of the program's own scenario,
		       measured by running it, plus the 21,000 intrinsic and
		       the calldata (EIP-2028) that a transaction also pays.

   **Measured, not modelled.** `solidity_evm.cjs` beside this file already
   compiled the contract with solc and replayed the scenario on a real EVM to
   check that the contract does what the program does; it now reports the
   sizes, solc's own static estimates and the gas each call used. This module
   builds the plan for it, runs it, and turns the answer into the notes the
   IDE and the CLI show. Nothing here estimates anything: where the numbers
   cannot be had — no node, no solc, no EVM — it says so and returns
   `not_measured/1` rather than guessing (design note
   E1).

   **solc's own estimates are reported and not relied on.** For the functions
   that matter they say "infinite", which means "not bounded by static
   analysis", not "expensive"; where they do give a number they assume the
   expensive case (cold slots, 0 → non-zero), so they are a ceiling. They are
   shown beside the measurement, and a warning is raised only where §2.1.5
   decision 4 says: when a measured call is within 20% of a budget the author
   stated.

   **The fork is an option and is printed with every figure** (decision 3).
   Every interesting cost — storage, cold/warm access, calldata — is fixed by
   the fork, and Glamsterdam will change the storage constants again.

   The call plan built here is the one the gate replays (lps_solidity_test.pl
   uses `solidity_call_plan/4`), so a cost report and a correctness check
   always describe the same calls.
*/

:- module(lps_solidity_cost, [
	solidity_cost/6,          % +Program, +Source, +Contract, +Iface, +Options, -Report
	cost_diags/3,             % +Report, +Options, -Diags
	cost_dict/2,              % +Report, -Dict
	solidity_call_plan/4,     % +Program, +Iface, -Calls, -Ctor
	call_json/3,              % +Actions, +Event, -CallDict   (the gate's, shared)
	arg_json/3,               % +Type, +Value, -Dict
	value_text/3,             % +Type, +Value, -Text
	name_text/2,              % +Name, -Text
	run_evm_plan/2,           % +Plan, -Out
	ensure_evm_modules/0,
	code_size_limit/2,        % ?Which, ?Bytes
	budget_goal/4,            % ?Goal, ?Which, ?Of, ?Number
	budget_constraint/2,      % +Conditions, -budget(Which, Of, Op, Limit)
	tx_gas_cap/1,             % ?Gas          EIP-7825
	default_block_gas_limit/1 % ?Gas          a figure, not a constant
	]).

/*  E2 — the budgets an author states, in the language
    (the design notes on language coverage, §2.1.5).

    Three system templates (i18n/system_templates.csv in LE2) let a program say
    what the contract it becomes may cost, in the same `it must not be true
    that` sentence as everything else it forbids:

	it must not be true that the gas of transfer is an amount
	    and the amount > 60000.
	it must not be true that the code size of the contract is an amount
	    and the amount > 20000.
	it must not be true that the call data of transfer is an amount bytes
	    and the amount > 200.

    LPS keeps them and does nothing with them (there is no contract in a run,
    and no gas model yet — §2.1.4's G2 — so LE2 says so instead of passing
    them silently). They are addressed here: each is checked against the
    measurement, and a broken one **refuses the export**, with the figure in
    the message. That is the refuse-before-emit pattern the exporter already
    uses for everything it cannot translate.

    Two limits are checked whether or not the author states them, because they
    are not opinions: EIP-170's 24,576 deployed bytes, above which there is no
    contract, and EIP-7825's per-transaction cap of 2^24 gas, above which a
    call can never be included. The **block** gas limit is not one of them:
    validators vote it, so it is a figure with a default, printed and
    configurable, never a hard-coded constant.
*/

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(yall)).
:- use_module(library(option)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- if(exists_source(library(json))).
:- use_module(library(json)).
:- else.
:- use_module(library(http/json)).
:- endif.
:- use_module(lps2_src(core/lps_diag)).
:- use_module(lps2_src(core/lps_program)).

:- dynamic here/1.
:- prolog_load_context(directory, D), retractall(here(D)), assertz(here(D)).

%!	code_size_limit(?Which, ?Bytes) is nondet.
%
%	The two limits that are not opinions. A contract whose deployed
%	bytecode exceeds EIP-170's figure cannot be deployed at all; one whose
%	initcode exceeds EIP-3860's cannot be sent. Both are consensus rules,
%	so breaking them is a refusal rather than a note.
code_size_limit(deployed, 24576).     % EIP-170
code_size_limit(creation, 49152).     % EIP-3860

%!	tx_gas_cap(?Gas) is det.
%
%	EIP-7825, since Fusaka: no transaction may declare a gas limit above
%	2^24, so a call that costs more than this can never be included, on any
%	chain that has the EIP. Like EIP-170 this is consensus, not preference.
tx_gas_cap(16777216).                 % 2^24

%!	default_block_gas_limit(?Gas) is det.
%
%	What a block holds, by default. This one is *not* a rule: validators
%	vote the block gas limit up and down, and it has moved several times in
%	2026. So it is a default that every report prints and any caller may
%	replace (`block_gas_limit(N)`), and nothing is refused for breaking it —
%	a call larger than a block is said, not forbidden.
default_block_gas_limit(45000000).

%!	budget_goal(?Goal, ?Which, ?Of, ?Number) is nondet.
%
%	The three budget conditions, as they reach an LPS program from LE2's
%	system templates. `Of` is the action's LPS functor (the `known as` name
%	the author writes) or, for the code size, the atom `contract`.
budget_goal(le_gas_of(Of, N),       gas,       Of,       N).
budget_goal(le_code_size(N),        code_size, contract, N).
budget_goal(le_call_data_of(Of, N), call_data, Of,       N).

%!	budget_constraint(+Conditions, -Budget) is semidet.
%
%	The conditions of an integrity constraint that states a budget, read as
%	`budget(Which, Of, Op, Limit)`: the sentence forbids `Limit Op` — so a
%	measured figure M breaks it exactly when `M Op Limit` is true, which is
%	how the check reads it back.
%
%	An unbound `Of` is the sentence that names the action in its other
%	conjunct — *an account transfers an amount to a second account and the
%	gas of the action is …* — and is resolved to that action here. With no
%	action in the constraint at all it stays unbound, and the budget is read
%	as one on every call.
budget_constraint(Cond, budget(Which, Of, Op, Limit)) :-
	is_list(Cond),
	member(G, Cond), budget_goal(G, Which, Of0, N), !,
	member(C, Cond), compound(C), C =.. [Op, L, R],
	memberchk(Op, [>, >=, <, =<, =:=]),
	L == N, ground(R), catch(Limit is R, _, fail),
	(   var(Of0)
	->  (   member(happens(E, _, _), Cond), callable(E), functor(E, F, _)
	    ->  Of = F
	    ;   Of = any
	    )
	;   Of = Of0
	).

%!	intrinsic_gas(+Calldata, -Gas) is det.
%
%	What a transaction pays before the first opcode: 21,000, plus 4 per
%	zero byte of calldata and 16 per non-zero one (EIP-2028). The EIP-7623
%	floor (a minimum priced per byte-token when execution is small) is not
%	applied: it raises the figure for data-heavy, computation-light calls,
%	and saying so is honester than a half-implemented floor.
intrinsic_gas(CD, Gas) :-
	( get_dict(zero, CD, Z) -> true ; Z = 0 ),
	( get_dict(nonzero, CD, NZ) -> true ; NZ = 0 ),
	Gas is 21000 + 4*Z + 16*NZ.

		 /*******************************
		 *	    the call plan	*
		 *******************************/

%!	solidity_call_plan(+Program, +Iface, -Calls, -Ctor) is det.
%
%	The program's own scenario as the EVM harness's calls, in observation
%	order, and the named accounts in the constructor's parameter order.
solidity_call_plan(P, iface(Acts, _Fls, Ctor), Calls, CtorT) :-
	findall(T-E, ( p_observe(P, Es, T), member(E, Es) ), TEs0), msort(TEs0, TEs),
	findall(C, ( member(_-E, TEs), call_json(Acts, E, C) ), Calls),
	maplist(name_text, Ctor, CtorT).

%!	call_json(+Actions, +Event, -Call) is semidet.
%
%	One observed event as a call of the generated contract. Moved here from
%	the gate so that the report and the replay cannot describe different
%	calls; the argument order is the generator's own (`abi_order/2`:
%	addresses first).
call_json(Acts, E, _{from: From, fn: Fn, args: Args}) :-
	functor(E, A, N), memberchk(act(A/N, Fn, Caller, Ts), Acts),
	E =.. [_|Vs0],
	(   Caller == true -> Vs0 = [W|Vs], Ts = [_|Ts1], name_text(W, From)
	;   Vs = Vs0, Ts1 = Ts, From = null
	),
	maplist(arg_json, Ts1, Vs, Args0),
	partition([J]>>get_dict(t, J, "address"), Args0, As, Rest0),
	partition([J]>>(get_dict(t, J, T), T == address), Rest0, As2, Rest),
	append([As, As2, Rest], Args).

arg_json(T, V, _{t: T, v: J}) :- value_text(T, V, J).

value_text(address, V, J) :- !, name_text(V, J).
value_text(_, V, J) :- ( number(V) -> number_string(V, J) ; atom(V) -> atom_string(V, J) ; J = V ).

name_text(V, "address(0)") :- atom(V), sub_atom(V, _, _, _, 'zero address'), !.
name_text(V, J) :- atom_string(V, J).

		 /*******************************
		 *	   running the EVM	*
		 *******************************/

%!	ensure_evm_modules is det.
%
%	Where the EVM's modules are, for the child process, which inherits this
%	environment. An LPS_EVM_MODULES already set wins; otherwise this
%	checkout's gitignored `build/evm`, which is where the install
%	instructions put them. The compiler (solc) is looked for there too;
%	when it is not there, in the Solidity reader's folder of a Logical
%	English checkout (migration/solidity/node_modules), which has one.
ensure_evm_modules :-
	lps2_build_evm(M),
	(   getenv('LPS_EVM_MODULES', _) -> true
	;   exists_directory(M) -> setenv('LPS_EVM_MODULES', M)
	;   true
	),
	(   getenv('LPS_SOLC_MODULES', _) -> true
	;   atom_concat(M, '/solc', Solc), exists_directory(Solc) -> true
	;   le2_solc_modules(S) -> setenv('LPS_SOLC_MODULES', S)
	;   true
	).

lps2_build_evm(M) :-
	here(Syntax), file_directory_name(Syntax, Src), file_directory_name(Src, L),
	atomic_list_concat([L, '/build/evm/node_modules'], M).

le2_solc_modules(S) :-
	(   member(V, ['LPS_LE2_LIB', 'LPS_LE2_DIR', 'LE2_DIR']), getenv(V, LE2), LE2 \== ''
	;   here(Syntax), file_directory_name(Syntax, Src), file_directory_name(Src, L),
	    file_directory_name(L, Parent),
	    member(N, ['LogicalEnglish2', 'LE2', le2, work]),
	    atomic_list_concat([Parent, '/', N], LE2)
	;   LE2 = '/work'
	),
	atomic_list_concat([LE2, '/migration/solidity/node_modules'], S),
	atom_concat(S, '/solc', Solc), exists_directory(Solc), !.

%!	run_evm_plan(+Plan, -Out) is det.
%
%	Runs `solidity_evm.cjs` on Plan. Out is the dict it printed, or
%	`skip(Why)` when a tool is missing, or `error(What)`.
run_evm_plan(Plan, Out) :-
	here(Dir),
	atomic_list_concat([Dir, '/solidity_evm.cjs'], Script),
	ensure_evm_modules,
	setup_call_cleanup(
	    tmp_file_stream(text, File, S),
	    ( json_write_dict(S, Plan, [width(0)]), close(S),
	      catch(( process_create(path(node), [Script, File],
				      [stdout(pipe(O)), stderr(null), process(Pid)]),
		      read_string(O, _, Str), close(O), process_wait(Pid, Status) ),
		    E, ( Status = error(E), Str = "" )) ),
	    delete_file(File)),
	(   Status == exit(3) -> Out = skip('solc is not installed (LPS_SOLC_MODULES)')
	;   Status = error(error(existence_error(source_sink, path(node)), _))
	->  Out = skip('node is not on the PATH')
	;   Status \== exit(0) -> Out = error(Status)
	;   catch(atom_json_dict(Str, Out, []), _, Out = error(Str))
	).

		 /*******************************
		 *	    the report		*
		 *******************************/

%!	solidity_cost(+Program, +Source, +Contract, +Iface, +Options, -Report) is det.
%
%	Report is `measured(Dict)` or `not_measured(Why)`. Options:
%	  - fork(F)             the hardfork to price at (default: the
%	                        harness's, `cancun`), reported in the Dict
%	  - optimizer_runs(N)   solc's optimiser runs (default 200)
solidity_cost(P, Source, Contract, Iface, Options, Report) :-
	solidity_call_plan(P, Iface, Calls, Ctor),
	option(fork(Fork), Options, cancun),
	option(optimizer_runs(Runs), Options, 200),
	atom_string(Fork, ForkS),
	Plan = _{source: Source, contract: Contract, ctor: Ctor, calls: Calls,
		 reads: [], fork: ForkS, optimizerRuns: Runs},
	run_evm_plan(Plan, Out),
	report_of(Out, Calls, Report).

report_of(skip(W), _, not_measured(W)) :- !.
report_of(error(E), _, not_measured(Msg)) :- !,
	format(atom(Msg), 'the measurement did not run (~w)', [E]).
report_of(Out, _, not_measured(Msg)) :-
	is_dict(Out), get_dict(compiled, Out, false), !,
	( get_dict(errors, Out, [E|_]) -> true ; E = 'the contract did not compile' ),
	first_line(E, Msg).
report_of(Out, Calls, measured(D)) :-
	is_dict(Out), get_dict(cost, Out, C), !,
	(   get_dict(calls, Out, Rs)
	->  maplist(call_row, Calls, Rs, Rows)
	;   Rows = []
	),
	D = C.put(_{calls: Rows}).
report_of(_, _, not_measured('the measurement returned nothing')).

first_line(E, L) :-
	atom_string(E, S), split_string(S, "\n", "", [L0|_]), atom_string(L, L0).

%	One call of the scenario, with what it cost: the execution gas the EVM
%	reported, the intrinsic the transaction would also pay, and the sum —
%	which is the number an author compares with a budget.
call_row(Call, R, Row) :-
	get_dict(fn, Call, Fn),
	( get_dict(from, Call, From0), From0 \== null -> From = From0 ; From = "" ),
	( get_dict(args, Call, As) -> maplist([A, V]>>get_dict(v, A, V), As, Vs) ; Vs = [] ),
	( get_dict(gas, R, GS) -> number_string(Gas, GS) ; Gas = 0 ),
	( get_dict(calldata, R, CD) -> intrinsic_gas(CD, In) ; In = 0, CD = _{bytes: 0, zero: 0, nonzero: 0} ),
	( get_dict(ok, R, Ok) -> true ; Ok = true ),
	Total is Gas + In,
	Row = _{fn: Fn, from: From, args: Vs, gas: Gas, intrinsic: In, total: Total,
		ok: Ok, calldata: CD}.

%!	cost_dict(+Report, -Dict) is det.
%
%	The report as the ledger keeps it.
cost_dict(measured(D), D) :- !.
cost_dict(not_measured(W), _{measured: false, reason: W}).

%!	cost_diags(+Report, +Options, -Diags) is det.
%
%	The report as the diagnostics the IDE and the CLI already know how to
%	show: `info` for every figure, `error` for the two size limits, which
%	are consensus rules rather than preferences. Options are passed through
%	from the export (`budgets/1` is read by the budget check, not here).
cost_diags(not_measured(W), Options, [D]) :- !,
	%  a program that *stated* a budget asked for this figure, and not having
	%  it is a thing it should hear about; a `--cost` run that cannot measure
	%  is merely a run that cannot measure
	( option(budgets(Bs), Options, []), Bs \== [] -> Sev = warning, Tail = ' The budgets this program states are therefore unchecked.' ; Sev = info, Tail = '' ),
	format(atom(M), 'the cost was not measured: ~w. Sizes and gas need node, solc and an EVM beside the translator.~w', [W, Tail]),
	diag(Sev, cost_not_measured, unknown, M, D).
cost_diags(measured(C), Options, Diags) :-
	findall(D, cost_diag(C, D), Ds),
	option(budgets(Bs), Options, []),
	findall(D, ( member(B, Bs), budget_diag(B, C, Options, D) ), BDs),
	findall(D, limit_diag(C, Options, D), LDs),
	append([Ds, BDs, LDs], Diags).

%	The header: nothing below means anything without it.
cost_diag(C, D) :-
	get_dict(solc, C, Solc),
	( get_dict(fork, C, Fork) -> true ; Fork = 'not run' ),
	( get_dict(optimizer, C, Opt), get_dict(runs, Opt, Runs) -> true ; Runs = 200 ),
	format(atom(M), 'cost: measured with solc ~w, optimiser ~w runs, at the ~w fork. Every figure below is that fork\'s.', [Solc, Runs, Fork]),
	diag(info, cost_header, unknown, M, D).
%	The sizes, with the headroom that decides whether there is a contract.
cost_diag(C, D) :-
	get_dict(size, C, Sz), get_dict(Which, Sz, Bytes),
	code_size_limit(Which, Limit),
	Pct is round(1000 * Bytes / Limit) / 10,
	size_word(Which, Word, Eip),
	(   Bytes > Limit
	->  format(atom(M), '~w is ~w bytes, over the ~w limit of ~w: this contract cannot be deployed.', [Word, Bytes, Eip, Limit]),
	    diag(error, code_size, unknown, M, D)
	;   format(atom(M), '~w: ~w bytes of the ~w limit of ~w (~w%).', [Word, Bytes, Eip, Limit, Pct]),
	    diag(info, code_size, unknown, M, D)
	).
%	What deploying it costs.
cost_diag(C, D) :-
	get_dict(deployGas, C, GS), number_string(G, GS),
	( get_dict(deployCalldata, C, CD) -> intrinsic_gas(CD, In) ; In = 0 ),
	T is G + In,
	format(atom(M), 'deployment: ~w gas of execution, ~w intrinsic and calldata, ~w in all.', [G, In, T]),
	diag(info, cost_deploy, unknown, M, D).
%	Every call of the program's own scenario.
cost_diag(C, D) :-
	get_dict(calls, C, Rows), Rows \== [],
	member(R, Rows),
	call_line(R, M),
	diag(info, cost_call, unknown, M, D).
%	solc's static estimates, and the fact that they are missing where they
%	would be most useful. Reported, never relied on (decision 4).
cost_diag(C, D) :-
	get_dict(estimates, C, E), E \== null,
	get_dict(external, E, Ext),
	dict_pairs(Ext, _, Pairs),
	findall(F, ( member(F-V, Pairs), V == "infinite" ), Inf),
	Inf \== [],
	atomic_list_concat(Inf, ', ', L),
	format(atom(M), 'solc could not bound these statically (it says "infinite", which means unbounded by its analysis, not expensive): ~w. The figures above are measurements, not estimates.', [L]),
	diag(info, cost_estimates, unknown, M, D).

size_word(deployed, 'the deployed bytecode', 'EIP-170').
size_word(creation, 'the creation code', 'EIP-3860').

		 /*******************************
		 *	  the budgets (E2)	*
		 *******************************/

%!	budget_diag(+Budget, +Cost, +Options, -Diag) is nondet.
%
%	One `budget(Which, Fn, Op, Limit)` against the measurement. A figure
%	that breaks the sentence is an **error** — the export refuses, and the
%	message carries the figure, because a budget whose breach you cannot see
%	is a budget you cannot act on. One that holds is reported too: an author
%	who wrote the sentence wants to know the headroom, and a budget that is
%	never mentioned again looks like one that was not read.
%
%	Decision 4 of §2.1.5: a measurement **within 20% of the budget** is a
%	warning rather than a note, and says so where solc could not bound the
%	function statically — the two together are how a contract quietly grows
%	past a limit between releases.
budget_diag(budget(code_size, _, Op, Limit), C, _, D) :-
	get_dict(size, C, Sz), get_dict(deployed, Sz, Bytes),
	Breach =.. [Op, Bytes, Limit],
	(   call(Breach)
	->  format(atom(M), 'the code size of the contract is ~w bytes, which the program forbids (it must not be ~w ~w). The contract is not written.', [Bytes, Op, Limit]),
	    diag(error, budget_code_size, unknown, M, D)
	;   near_budget(Bytes, Limit)
	->  pct(Bytes, Limit, Pct),
	    format(atom(M), 'the code size of the contract is ~w bytes, against the ~w this program allows: ~w% of it. A release or two of growth and the export refuses.', [Bytes, Limit, Pct]),
	    diag(warning, budget_code_size, unknown, M, D)
	;   format(atom(M), 'the code size of the contract is ~w bytes, against the ~w this program allows.', [Bytes, Limit]),
	    diag(info, budget_code_size, unknown, M, D)
	).
budget_diag(budget(Which, Fn, Op, Limit), C, Options, D) :-
	memberchk(Which, [gas, call_data]),
	get_dict(calls, C, Rows),
	member(R, Rows), get_dict(fn, R, F),
	( Fn == any -> true ; F == Fn ),
	budget_figure(Which, R, Value),
	call_line_head(R, Head),
	Breach =.. [Op, Value, Limit],
	budget_words(Which, Word, Unit),
	(   call(Breach)
	->  format(atom(M), '~w: ~w is ~w ~w, which the program forbids (it must not be ~w ~w). The contract is not written.',
		   [Head, Word, Value, Unit, Op, Limit]),
	    diag(error, budget_breach, unknown, M, D)
	;   near_budget(Value, Limit)
	->  unbounded_note(F, C, Options, Extra),
	    pct(Value, Limit, Pct),
	    format(atom(M), '~w: ~w is ~w ~w, ~w% of the ~w this program allows~w.',
		   [Head, Word, Value, Unit, Pct, Limit, Extra]),
	    diag(warning, budget_near, unknown, M, D)
	;   format(atom(M), '~w: ~w is ~w ~w, of the ~w this program allows.',
		   [Head, Word, Value, Unit, Limit]),
	    diag(info, budget_within, unknown, M, D)
	).

%	A budget nothing measured. The scenario may make no such call, or the
%	EVM may not have run — either way the sentence was not checked, and an
%	author who wrote it should not be left thinking it was.
budget_diag(budget(Which, Fn, _, Limit), C, _, D) :-
	memberchk(Which, [gas, call_data]),
	\+ (   get_dict(calls, C, Rows), member(R, Rows), get_dict(fn, R, F),
	       ( Fn == any -> true ; F == Fn )
	   ),
	budget_words(Which, Word, _),
	format(atom(M), '~w of ~w is budgeted at ~w and nothing measured it: the program''s scenario makes no such call, or the EVM did not run.',
	       [Word, Fn, Limit]),
	diag(warning, budget_unchecked, unknown, M, D).

%	Gas is what the sender is charged — execution plus the intrinsic and the
%	calldata — because that is the figure an author means by "the gas of a
%	call" and the one a wallet shows.
budget_figure(gas, R, V) :- get_dict(total, R, V).
budget_figure(call_data, R, V) :-
	( get_dict(calldata, R, CD), get_dict(bytes, CD, V0) -> V = V0 ; V = 0 ).

budget_words(gas, 'the gas', 'in all (execution, intrinsic and calldata)').
budget_words(call_data, 'the call data', bytes).

near_budget(V, L) :- L > 0, V =< L, V >= 0.8 * L.

pct(V, L, Pct) :- Pct is round(1000 * V / L) / 10.

%	Decision 4: solc's "infinite" is not a warning by itself — it means
%	"unbounded by static analysis" — but beside a call already near its
%	budget it is the thing worth saying, because nothing static will catch
%	the release that goes over.
unbounded_note(Fn, C, _Options, Extra) :-
	(   get_dict(estimates, C, E), E \== null, get_dict(external, E, Ext),
	    dict_pairs(Ext, _, Pairs),
	    member(Sig-"infinite", Pairs), sub_atom(Sig, 0, _, _, Fn)
	->  Extra = ', and solc cannot bound it statically ("infinite"): nothing but a measurement will catch the release that goes over'
	;   Extra = ''
	).

call_line_head(R, Head) :-
	get_dict(fn, R, Fn), get_dict(args, R, Vs), get_dict(from, R, From),
	atomic_list_concat(Vs, ', ', A),
	( From == "" -> Who = '' ; format(atom(Who), '~w: ', [From]) ),
	format(atom(Head), '~w~w(~w)', [Who, Fn, A]).

		 /*******************************
		 *   the limits nobody votes	*
		 *******************************/

%!	limit_diag(+Cost, +Options, -Diag) is nondet.
%
%	EIP-7825's per-transaction gas cap, checked whether or not the program
%	says anything: above 2^24 a transaction cannot be included, so a call
%	that costs more is a contract with a function nobody can call. And the
%	block gas limit, which is *not* a rule — validators vote it — reported
%	as the figure it is, with the default this deployment used.
limit_diag(C, _, D) :-
	tx_gas_cap(Cap),
	(   get_dict(deployGas, C, GS), number_string(G, GS),
	    ( get_dict(deployCalldata, C, CD) -> intrinsic_gas(CD, In) ; In = 0 ),
	    T is G + In, T > Cap
	->  format(atom(M), 'deploying this contract costs ~w gas, above the ~w a transaction may declare (EIP-7825): it cannot be deployed in one transaction.', [T, Cap]),
	    diag(error, tx_gas_cap, unknown, M, D)
	).
limit_diag(C, _, D) :-
	tx_gas_cap(Cap),
	get_dict(calls, C, Rows), member(R, Rows),
	get_dict(total, R, T), T > Cap,
	call_line_head(R, Head),
	format(atom(M), '~w costs ~w gas, above the ~w a transaction may declare (EIP-7825): no chain with that EIP can include this call.', [Head, T, Cap]),
	diag(error, tx_gas_cap, unknown, M, D).
limit_diag(C, Options, D) :-
	default_block_gas_limit(Def),
	option(block_gas_limit(BL), Options, Def),
	most_expensive(C, T, Head), T > BL / 2,
	Pct is round(1000 * T / BL) / 10,
	format(atom(M), 'the most expensive thing here, ~w at ~w gas, is ~w% of a ~w block. The block gas limit is voted by validators, not fixed: this is the figure this report assumed, and block_gas_limit(N) changes it.', [Head, T, Pct, BL]),
	diag(warning, block_gas_share, unknown, M, D).

most_expensive(C, T, Head) :-
	findall(G-H,
		(   get_dict(deployGas, C, GS), number_string(G0, GS),
		    ( get_dict(deployCalldata, C, CD) -> intrinsic_gas(CD, In) ; In = 0 ),
		    G is G0 + In, H = 'the deployment'
		;   get_dict(calls, C, Rows), member(R, Rows),
		    get_dict(total, R, G), call_line_head(R, H)
		), Ps),
	Ps \== [],
	sort(1, @>=, Ps, [T-Head|_]).

call_line(R, M) :-
	get_dict(fn, R, Fn), get_dict(args, R, Vs), get_dict(from, R, From),
	get_dict(gas, R, G), get_dict(intrinsic, R, In), get_dict(total, R, T),
	get_dict(ok, R, Ok),
	atomic_list_concat(Vs, ', ', A),
	( From == "" -> Who = '' ; format(atom(Who), '~w: ', [From]) ),
	( Ok == true -> Rev = '' ; Rev = ' — it reverted, and on chain the intrinsic is paid anyway' ),
	format(atom(M), '~w~w(~w): ~w gas of execution, ~w intrinsic and calldata, ~w in all~w.',
	       [Who, Fn, A, G, In, T, Rev]).

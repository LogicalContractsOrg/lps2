/* solidity_test.pl — the gate for Misc ▸ Deploy as Solidity.

   src/syntax/lps_solidity.pl writes an LPS program as a Solidity contract, or
   refuses with the reasons. This gate checks both halves:

   1. **Refusals.** Small programs, each with one feature that has no straight
      translation (a reactive rule, a fraction, an enumeration, an event of the
      environment, planning), must be refused with that feature's code — and a
      small compatible program written in LPS syntax must not be.

   2. **The corpus translates, compiles and behaves.** The Solidity twins of
      examples/migration/solidity (OpenZeppelin ERC-20, Ownable, Pausable, their Wizard
      composition, Circle's FiatToken — Logical English for LPS, read from
      deployed Solidity by InsurLE2/migration/solidity) are written back as
      Solidity; each must compile with solc with no warning; and, on an
      in-process EVM, the program's own scenario replayed as calls must leave
      the contract in the state LPS2's run of the program ends in — every fact
      of LPS2's final state read back through the contract's getters, and every
      absent key (over the names the scenario mentions) absent there too. The
      same refusals LPS2 makes (a constraint violated) are the EVM's reverts.

	LPS_LE2_LIB=<an LE2 checkout> ./myswipl.sh -q -g "consult('tools/solidity_test.pl')" -g "solt:main" -t halt

   The corpus needs LE2 (LPS_LE2_LIB) and the twins (examples/migration/solidity,
   or LPS_SOLIDITY_TWINS); solc comes from InsurLE2/migration/solidity/node_modules
   (or LPS_SOLC_MODULES); the EVM from build/evm/node_modules (or
   LPS_EVM_MODULES; `npm i --prefix build/evm @ethereumjs/vm@10
   @ethereumjs/common@10 @ethereumjs/util@10`). What is missing is skipped
   and said so, never counted as a pass.
*/

:- module(solt, [main/0]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(http/json)).
:- use_module('../src/core/lps_diag').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_program').
:- use_module('../src/syntax/lps_solidity').
:- use_module('../src/edges/lps_le').
:- use_module('../src/edges/lps_cli', []).
:- use_module('../src/edges/lps_source').

:- dynamic result/2.

main :-
	retractall(result(_, _)),
	forall(refusal_case(Name, Src, Code), refusal(Name, Src, Code)),
	compatible_lps,
	corpus,
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
	->  lps_to_solidity(P, [origin('t.lps')], R),
	    (   R = refused(Ds), member(D, Ds), diag_code(D, Code)
	    ->  record(refuses(Name), pass)
	    ;   R = refused(Ds)
	    ->  maplist(diag_code, Ds, Cs), record(refuses(Name), wrong_codes(Cs))
	    ;   record(refuses(Name), not_refused)
	    )
	;   record(refuses(Name), did_not_compile)
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
	;   module_property(solt, file(F)), file_directory_name(F, Tools),
	    file_directory_name(Tools, Root),
	    atomic_list_concat([Root, '/examples/migration/solidity'], R)
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
	    lps_to_solidity(P, [interface(I), templates(Ts), source(Text), origin(F)], solidity(Sol0, C, _)),
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
		 *   generate, compile, replay	*
		 *******************************/

check_program(Name, P, Opts) :-
	lps_to_solidity(P, [interface(I)|Opts], R),
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
plan(P, iface(Acts, Fls, Ctor), Sol, Contract, Final, Plan, Expect) :-
	findall(T-E, ( p_observe(P, Es, T), member(E, Es) ), TEs0), msort(TEs0, TEs),
	findall(C, ( member(_-E, TEs), call_json(Acts, E, C) ), Calls),
	names_seen(Acts, Fls, TEs, Final, Ctor, Names),
	findall(Rd-X, ( member(Fl, Fls), fluent_reads(Fl, Final, Names, Rd, X) ), RXs),
	pairs_keys_values(RXs, Reads, Expect),
	maplist(name_text, Ctor, CtorT),
	Plan = _{source: Sol, contract: Contract, ctor: CtorT, calls: Calls, reads: Reads}.

call_json(Acts, E, _{from: From, fn: Fn, args: Args}) :-
	functor(E, A, N), memberchk(act(A/N, Fn, Caller, Ts), Acts),
	E =.. [_|Vs0],
	(   Caller == true -> Vs0 = [W|Vs], Ts = [_|Ts1], name_text(W, From)
	;   Vs = Vs0, Ts1 = Ts, From = null
	),
	maplist(arg_json, Ts1, Vs, Args0),
	%  the generator's interface order: addresses first (lps_solidity:abi_order/2)
	partition([J]>>get_dict(t, J, "address"), Args0, As, Rest0),
	partition([J]>>(get_dict(t, J, T), T == address), Rest0, As2, Rest),
	append([As, As2, Rest], Args).

arg_json(T, V, _{t: T, v: J}) :- value_text(T, V, J).

value_text(address, V, J) :- !, name_text(V, J).
value_text(_, V, J) :- ( number(V) -> number_string(V, J) ; atom(V) -> atom_string(V, J) ; J = V ).

name_text(V, "address(0)") :- atom(V), sub_atom(V, _, _, _, 'zero address'), !.
name_text(V, J) :- atom_string(V, J).

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

run_evm(Plan, Out) :-
	tmp_file_stream(text, File, S),
	json_write_dict(S, Plan, [width(0)]), close(S),
	prolog_load_context_dir(Dir),
	atomic_list_concat([Dir, '/solidity_evm.cjs'], Script),
	catch(( process_create(path(node), [Script, File], [stdout(pipe(O)), stderr(null), process(Pid)]),
		read_string(O, _, Str), close(O), process_wait(Pid, Status) ),
	      E, ( Status = error(E), Str = "" )),
	delete_file(File),
	(   Status == exit(3) -> Out = skip('solc not found')
	;   Status \== exit(0) -> Out = error(Status)
	;   catch(atom_json_dict(Str, Out, []), _, Out = error(Str))
	).

:- dynamic here/1.
:- prolog_load_context(directory, D), retractall(here(D)), assertz(here(D)).
prolog_load_context_dir(D) :- here(D).

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

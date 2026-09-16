/* lps_solidity.pl — an LPS program, written out as a Solidity contract.

   The *reverse* of the Solidity front end in InsurLE2 (migration/solidity,
   sol_front.pl), which reads a deployed contract as LPS: here a program that
   was written — or reviewed — as LPS goes out to the EVM. It is the IDE's
   Misc ▸ Deploy as Solidity (docs/UsingTheIDE.md) and `lps solidity FILE`.

   The mapping is fixed, and it is the front end's, read backwards:

     fluent f            (arity 0)       bool f
     fluent f(K…, V)     functional      mapping(K… => V) f   + mapping(K… => bool) hasF
     fluent f(V)         functional      V f                   + bool hasF
     fluent f(A…)        a set           mapping(A… => bool) f
     action a(Caller, P…)                function a(P…) external, Caller = msg.sender
     d_pre on one action (current state) if (<conditions>) revert <Error>();  at entry
     d_pre on one action (next state)    the same, after the writes
     d_pre naming no action              an invariant checked after every call
     initiated / terminated / updated    state writes, in LPS2's own order
     initial_state                       the constructor
     observe                             a comment: the scenario, as calls to make

   **The order of a call's writes is LPS2's, not a guess.** One action is
   applied as lps_cycle.pl:apply_serial_action/2 applies it: every law's
   conditions are read on the state *before* the call, then the terminations
   are written, then the initiations (an initiation of a fact already there is
   no change), then the updates, each reading the value the earlier writes
   left (which is how two updates of one entry compose, as the EVM's two
   storage writes do). So the function evaluates each law's conditions into a
   local first, snapshots the values its writes need, and only then writes.

   **A fluent is a function only when the program shows it is one.** LPS
   fluents are relations; a Solidity mapping holds one value per key. A fluent
   `f(K…, V)` is written as a mapping from K… to V when every initiation of it
   is guarded by the key's absence or paired, in the same action, with a
   termination that clears the key — the two ways a program says "one value" —
   and no initial state gives a key two values. Anything else is a set, and a
   set read with an unbound argument would need enumeration, which a mapping
   cannot do: that is a refusal, not an approximation.

   **Absence is kept.** A fluent can be absent in LPS and a mapping cannot
   (every key maps to zero), and programs translated from Solidity say so
   explicitly (`… if it is not the case that the balance of the recipient is
   an amount`). The presence map `hasF` makes the contract answer those
   conditions as LPS does.

   **Unless the fluent has a default.** A fluent declared with one
   (`defaults/1`, LE2's `; 0 by default`) is total, as a mapping is: when
   its default is the zero of its type (0, the zero address, false, the
   empty text) it is written as the mapping alone, with no presence map —
   Solidity's own default is the declaration. Any other default is refused:
   the contract would need an "initialised" flag per key, which is exactly
   the presence map the default was meant to remove.

   **Refusal before translation.** `lps_to_solidity/3` first lists everything
   that has no straight translation — reactive rules, intensional fluents,
   composite events, planning, environment events, Prolog, timeless rules,
   enumeration, non-integer arithmetic, constraints over two actions — each
   with the line it comes from, and writes nothing when the list is not empty.
   A contract that meant something else than its program would be worse than
   none: this is money.
*/

:- module(lps_solidity, [
	lps_to_solidity/3,       % +Program, +Options, -Result
	solidity_sandbox_url/2,  % +SolidityText, -URL
	solidity_sandbox/2       % ?Key, ?Value
	]).

:- use_module(library(pcre)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(option)).
:- use_module(library(assoc)).
:- use_module(library(ugraphs)).
:- use_module(library(base64)).
:- use_module('../core/lps_diag').
:- use_module('../core/lps_program').

%!	solidity_sandbox(?Key, ?Value) is nondet.
%
%	The public sandbox the IDE opens a generated contract in: Remix IDE, the
%	Ethereum Foundation's browser IDE. It takes the source in the address
%	itself (`#code=<base64>`, loaded into a workspace called code-sample),
%	compiles it in the page and deploys to an in-browser chain (Remix VM)
%	with funded test accounts — nothing to install, no wallet, no network.
%	Its home is app.remix.live since September 2026 (remix.ethereum.org
%	redirects there, reloading the page: the address is kept).
solidity_sandbox(name, 'Remix IDE').
solidity_sandbox(base, 'https://app.remix.live/').
solidity_sandbox(docs, 'https://remix-ide.readthedocs.io/en/latest/locations.html').

%!	solidity_sandbox_url(+Text, -URL) is det.
solidity_sandbox_url(Text, URL) :-
	solidity_sandbox(base, Base),
	base64_encoded(Text, B64, [encoding(utf8)]),
	%  percent-encoded, as encodeURIComponent would: base64's + / = survive
	%  Remix's reading of the address only that way (checked in a browser)
	atom_codes(B64, Cs), foldl(pct, Cs, Out, []), atom_codes(Enc, Out),
	atomic_list_concat([Base, '#code=', Enc, '&autoCompile=true'], URL).

pct(0'+, [0'%, 0'2, 0'B|T], T) :- !.
pct(0'/, [0'%, 0'2, 0'F|T], T) :- !.
pct(0'=, [0'%, 0'3, 0'D|T], T) :- !.
pct(C, [C|T], T).

:- thread_local
	s_problem/3,             % Code, Message, Src
	s_note/3,                % Code, Message, Src
	s_clause/5,              % Id, Kind, Term, Src, Index
	s_edge/2,                % Node, Node
	s_seed/2,                % Node, Seed
	s_type/2,                % Node, Type          (after inference)
	s_caller/1,              % A/N
	s_fluent/3,              % F/N, Shape, ValuePos
	s_action/1,              % A/N
	s_account/2,             % Atom, Name          (named addresses)
	s_account_used/1,        % Atom                (read by a function)
	s_symbol/2,              % Atom, Name          (bytes32 constants)
	s_error/3,               % Name, Line, Text
	s_helper/1,              % min | max
	s_name/2,                % Kind-Key, Name      (identifiers issued)
	s_default/2,             % F/N, Default        (a fluent declared with one)
	s_constant/3.            % F/1, Value, Name    (a named constant: a one-row, one-place table)

reset :-
	retractall(s_problem(_, _, _)), retractall(s_note(_, _, _)),
	retractall(s_clause(_, _, _, _, _)), retractall(s_edge(_, _)),
	retractall(s_seed(_, _)), retractall(s_type(_, _)),
	retractall(s_caller(_)), retractall(s_fluent(_, _, _)),
	retractall(s_action(_)), retractall(s_account(_, _)),
	retractall(s_account_used(_)), retractall(s_symbol(_, _)),
	retractall(s_error(_, _, _)), retractall(s_helper(_)),
	retractall(s_name(_, _)), retractall(s_default(_, _)), retractall(s_constant(_, _, _)).

problem(Code, Src, Fmt, Args0) :-
	maplist(fmt_arg, Args0, Args),
	format(atom(M), Fmt, Args),
	( s_problem(Code, M, Src) -> true ; assertz(s_problem(Code, M, Src)) ).
note(Code, Src, Fmt, Args0) :-
	maplist(fmt_arg, Args0, Args),
	format(atom(M), Fmt, Args),
	( s_note(Code, M, Src) -> true ; assertz(s_note(Code, M, Src)) ).

%!	lps_to_solidity(+Program, +Options, -Result) is det.
%
%	Result is `solidity(Text, Contract, Notes)` or `refused(Problems)`, the
%	notes and problems being lps_diag `diag/5` terms (info and error).
%	Options:
%	  - contract(Name)   the contract's name (default: from origin, or Program)
%	  - templates(Ts)    LE2's le_template/6 terms of a Logical English
%			     document: parameter names and the sentences quoted
%			     in the contract's comments
%	  - source(Text)     the document's text, whose lines the comments quote
%	  - origin(Name)     the document's name, for the header
lps_to_solidity(P, Options, Result) :-
	setup_call_cleanup(
	    reset,
	    lps_to_solidity_(P, Options, Result),
	    reset).

lps_to_solidity_(P, Options, Result) :-
	collect(P),
	(   no_lps_program
	->  %  Not an LPS program at all (a Logical English document answered by
	    %  queries, say): one sentence, not a list of everything else it has.
	    diag(error, not_lps, unknown,
		 'this is not an LPS program with actions: nothing in it is a call a contract could answer. Deploy the LPS program itself (for a legal view, the program it was derived from).', D),
	    Result = refused([D])
	;   lps_to_solidity_checked(P, Options, Result)
	).

no_lps_program :-
	\+ s_action(_),
	\+ ( member(K, [reactive, l_int, l_events, initiated, terminated, updated, d_pre, initial, observe]),
	     s_clause(_, K, _, _, _) ).

lps_to_solidity_checked(P, Options, Result) :-
	check_program(P),
	infer_types,
	classify_fluents,
	check_clauses,
	(   s_problem(_, _, _)
	->  findall(D, ( s_problem(C, M, S), diag(error, C, S, M, D) ), Ds),
	    Result = refused(Ds)
	;   catch(generate(P, Options, Text, Contract), E, true),
	    (   var(E), \+ s_problem(_, _, _)
	    ->  findall(D, ( s_note(C, M, S), diag(info, C, S, M, D) ), Notes),
		Result = solidity(Text, Contract, Notes),
		( option(interface(I), Options) -> interface(I) ; true )
	    ;   ( nonvar(E) -> message_to_atom(E, EM), problem(internal, unknown, 'the generator failed: ~w', [EM]) ; true ),
		findall(D, ( s_problem(C, M, S), diag(error, C, S, M, D) ), Ds),
		Result = refused(Ds)
	    )
	).

message_to_atom(E, A) :- format(atom(A), '~q', [E]).

%	The contract's shape, for a caller that drives it (tools/solidity_test.pl
%	replays the program's scenario on an EVM):
%	  iface(Actions, Fluents, Ctor)
%	  Actions: act(F/N, Function, Caller, PositionTypes)  Caller true|false
%	  Fluents: fl(F/N, Shape, ValuePos, Getter, Presence, PositionTypes)
%	  Ctor:    the named accounts, in the constructor's parameter order
interface(iface(Acts, Fls, Ctor)) :-
	findall(act(A/N, Fn, Caller, Ts),
		( s_action(A/N), action_name(A/N, Fn),
		  ( s_caller(A/N) -> Caller = true ; Caller = false ),
		  findall(T, ( between(1, N, I), node_type(slot(ac(A/N), I), T0), sol_type(T0, T) ), Ts) ),
		Acts),
	findall(fl(F/N, Shape, VP, G, H, Ts),
		( s_fluent(F/N, Shape, VP), fluent_name(F/N, G),
		  ( s_default(F/N, D) -> H = default(D) ; s_name(has(F/N), H) -> true ; H = G ),
		  findall(T, ( between(1, N, I), node_type(slot(fl(F/N), I), T0), sol_type(T0, T) ), Ts) ),
		Fls),
	findall(Nm-A, s_account(A, Nm), NAs0), sort(NAs0, NAs),
	pairs_values(NAs, Ctor).

		 /*******************************
		 *	     collecting		*
		 *******************************/

%	Every clause of interest, numbervar'd (variables become '$VAR'(K), each
%	clause its own numbering) under an id, with where it came from.
collect(P) :-
	prog_provenance(P, Prov),
	forall(( member(prov(N, I, T, Src), Prov), family_kind(N, Kind) ),
	       add_clause(Kind, T, Src, I)),
	arg(18, P, decls(_, _, A1, AL, _, _, _, _)),
	forall(( ( member(A, A1) ; member(L, AL), member(A, L) ),
		 callable(A), functor(A, F, Ar) ),
	       ( s_action(F/Ar) -> true ; assertz(s_action(F/Ar)) )),
	constants,
	p_defaults(P, Ds),
	forall(( member(D, Ds), functor(D, F, N), arg(N, D, V) ),
	       (   zero_default(V)
	       ->  assertz(s_default(F/N, V))
	       ;   problem(default_not_zero, unknown,
			   'the fluent ~w/~w holds ~q by default; a mapping holds the zero of its type (0, the zero address, false, an empty text), and no other default has a straight translation.',
			   [F, N, V])
	       )).

%	A named constant (LE2's `the constants are:`, whose `the unlimited
%	allowance is 115…` is the timeless fact the_value_of_the_unlimited_
%	allowance_is(115…)): a timeless predicate of one place with one number
%	fact. It is a Solidity `constant`, and a condition that reads it names
%	it rather than looking it up.
constants :-
	forall(( s_clause(_, timeless, l_timeless(H, B), _, _), ( B == true ; B == [] ),
		 functor(H, F, 1), arg(1, H, V), number(V),
		 \+ ( s_clause(_, timeless, l_timeless(H2, _), _, _), functor(H2, F, 1), H2 \== H ),
		 \+ s_constant(F/1, _, _) ),
	       ( constant_want(F, Want), issue_name(constant(F/1), Want, Name),
		 assertz(s_constant(F/1, V, Name)) )).

%	the_value_of_the_unlimited_allowance_is -> THE_UNLIMITED_ALLOWANCE
constant_want(F, Want) :-
	atomic_list_concat(Ws0, '_', F),
	(   append([the, value, of], Rest, Ws0), append(Mid, [is], Rest), Mid \== [] -> Ws = Mid ; Ws = Ws0 ),
	atomic_list_concat(Ws, '_', W0), upcase_atom(W0, Want).

constant_goal(G, Name) :-
	compound(G), functor(G, F, 1), s_constant(F/1, _, Name).

%	The zero of a Solidity type, as an LPS default can write it.
zero_default(0).
zero_default(false).
zero_default("").
zero_default('').
zero_default(A) :- zero_address(A).

family_kind(1, reactive).
family_kind(2, reactive).
family_kind(3, l_int).
family_kind(4, l_events).
family_kind(5, timeless).
family_kind(6, initiated).
family_kind(7, terminated).
family_kind(8, updated).
family_kind(9, d_pre).
family_kind(10, initial).
family_kind(11, observe).
family_kind(21, user).

add_clause(user, T0, Src, I) :-
	( T0 = p(T1, _) -> true ; T1 = T0 ),
	%  a Logical English program's timeless facts arrive as the program's own
	%  Prolog: a ground fact is a row of a lookup table all the same
	T1 \= (_ :- _), callable(T1), ground(T1), \+ p_program_predicate(T1),
	\+ functor(T1, display, 2), !,
	add_clause(timeless, l_timeless(T1, true), Src, I).
add_clause(Kind, T0, Src, I) :-
	( T0 = p(T1, _) -> true ; T1 = T0 ),
	copy_term(T1, T),
	numbervars(T, 0, _),
	flag(lps_solidity_clause, Id, Id + 1),
	assertz(s_clause(Id, Kind, T, Src, I)).

src_line(src(_, L, _, _), L) :- integer(L), !.
src_line(_, 0).

		 /*******************************
		 *	  what cannot be moved	*
		 *******************************/

check_program(P) :-
	forall(s_clause(_, reactive, _, Src, _),
	       problem(reactive_rule, Src,
		       'a reactive rule (if … then …): a contract does nothing on its own — it only answers calls.',
		       [])),
	forall(s_clause(_, l_int, _, Src, _),
	       problem(intensional_fluent, Src,
		       'an intensional fluent (a fluent defined by a rule) would have to be recomputed at every read.',
		       [])),
	forall(s_clause(_, l_events, _, Src, _),
	       problem(composite_event, Src,
		       'a composite event (an event defined by a rule over time) has no counterpart in a call.',
		       [])),
	(   prog_setting(P, engine, Mode), Mode \== reactive
	->  problem(planning, unknown, 'the program plans (lps_engine ~w): a contract cannot search for a plan.', [Mode])
	;   true
	),
	(   catch(prog_module(P, M), _, fail), catch(M:achieve(_), _, fail)
	->  problem(planning, unknown, 'the program has a goal to achieve: a contract cannot plan.', [])
	;   true
	),
	arg(18, P, decls(_, _, _, _, E1, EL, PEL, UL)),
	forall(( ( member(E, E1) ; member(L, EL), member(E, L) ), callable(E),
		 functor(E, EF, EA), \+ s_action(EF/EA) ),
	       ( event_used(EF/EA)
	       ->  problem(environment_event, unknown,
			   'the event ~w/~w is something the environment observes, not a call someone makes: a contract has no way to be told of it (model it as an action of whoever reports it).',
			   [EF, EA])
	       ;   note(unused_event, unknown, 'the declared event ~w/~w is not used and is left out.', [EF, EA])
	       )),
	(   ( PEL = [_|_] ; UL = [_|_] )
	->  problem(prolog_events, unknown, 'prolog_events / unserializable declarations are engine plumbing with no contract counterpart.', [])
	;   true
	),
	forall(( s_clause(_, user, T, Src, _), user_clause_head(T, H),
		 \+ p_program_predicate(H),
		 functor(H, HF, HA), \+ memberchk(HF/HA, [display/2]) ),
	       (   T = (_ :- _)
	       ->  problem(timeless_rule, Src,
			   'a timeless rule (~w/~w): only facts can be written, as lookup tables — a rule would be a search at every call.', [HF, HA])
	       ;   problem(prolog, Src,
			   'the program''s own Prolog (~w/~w) cannot run on the EVM.', [HF, HA])
	       )),
	(   s_clause(_, user, T2, _, _), user_clause_head(T2, H2), functor(H2, display, 2)
	->  note(display, unknown, 'display/2 (the picture) is left out: a contract has no screen.', [])
	;   true
	),
	forall(( s_clause(_, timeless, l_timeless(H, B), Src, _), B \== true, B \== [] ),
	       problem(timeless_rule, Src,
		       'a timeless rule (~w) — only ground timeless facts are written, as lookups.', [short(H)])).

user_clause_head((H :- _), H) :- !.
user_clause_head(H, H).

event_used(F/A) :-
	functor(E, F, A),
	(   s_clause(_, Kind, T, _, _), memberchk(Kind, [initiated, terminated, updated, d_pre]),
	    sub_term(happens(E0, _, _), T), subsumes_term(E, E0)
	;   s_clause(_, observe, observe(Es, _), _, _), member(E0, Es), subsumes_term(E, E0)
	), !.

%	short(T) in a message's arguments: the term, as the program reads.
fmt_arg(short(T), A) :- !,
	format(atom(A), '~W', [T, [numbervars(true), quoted(true), max_depth(8), portray(true)]]).
fmt_arg(A, A).

		 /*******************************
		 *	   type inference	*
		 *******************************/

/*  Every argument position of a fluent, action or timeless predicate is a
    node; so is every variable of every clause. A variable in a position, two
    variables compared or equated, a variable and an arithmetic expression:
    edges. Constants are seeds: an integer says number, a string text, an atom
    a symbol. A component's type is its seeds' — a symbol that reaches an
    action's caller position (or is the zero address) is an address, any other
    symbol a bytes32 name. Mixed seeds are a refusal. */

infer_types :-
	forall(s_clause(Id, Kind, T, Src, _), clause_edges(Kind, Id, T, Src)),
	findall(A-B, s_edge(A, B), Es0),
	findall(B-A, s_edge(A, B), Es1),
	findall(N, ( s_edge(N, _) ; s_edge(_, N) ; s_seed(N, _) ), Ns0),
	sort(Ns0, Ns),
	append(Es0, Es1, Es),
	vertices_edges_to_ugraph(Ns, Es, G),
	components(Ns, G, Comps),
	%  callers: an action's first position whose component is a symbol, or
	%  carries no evidence at all
	forall(( s_action(A/N), N >= 1,
		 \+ ( member(C, Comps), memberchk(slot(ac(A/N), 1), C),
		      comp_seeds(C, Seeds), ( memberchk(num, Seeds) ; memberchk(str, Seeds) ) ) ),
	       assertz(s_caller(A/N))),
	forall(member(C, Comps), type_component(C)).

components([], _, []).
components([N|Ns], G, [C|Cs]) :-
	reachable(N, G, C0), sort(C0, C),
	ord_subtract(Ns, C, Rest),
	components(Rest, G, Cs).

comp_seeds(C, Seeds) :-
	findall(S, ( member(N, C), s_seed(N, S0), seed_kind(S0, S) ), Seeds0),
	sort(Seeds0, Seeds).

seed_kind(sym(_), sym) :- !.
seed_kind(S, S).

type_component(C) :-
	comp_seeds(C, Seeds),
	(   memberchk(flt, Seeds)
	->  comp_where(C, W),
	    problem(non_integer, unknown, 'a non-integer number (~w): the EVM has integers only.', [W]),
	    Type = int256
	;   memberchk(num, Seeds), ( memberchk(sym, Seeds) ; memberchk(str, Seeds) )
	->  comp_where(C, W),
	    problem(mixed_types, unknown, 'the same position holds numbers and names (~w): no one Solidity type fits.', [W]),
	    Type = uint256
	;   memberchk(num, Seeds)
	->  ( memberchk(neg, Seeds) -> Type = int256 ; Type = uint256 )
	;   memberchk(str, Seeds), memberchk(sym, Seeds)
	->  Type = string
	;   memberchk(str, Seeds)
	->  Type = string
	;   ( member(slot(ac(AF/AN), 1), C), s_caller(AF/AN)
	    ; member(Nd, C), s_seed(Nd, sym(Z)), zero_address(Z) )
	->  Type = address
	;   memberchk(sym, Seeds)
	->  Type = bytes32
	;   Type = uint256
	),
	forall(member(Node, C), assertz(s_type(Node, Type))).

comp_where(C, W) :-
	(   member(slot(K, I), C) -> format(atom(W), '~w, position ~w', [K, I]) ; W = 'a variable' ).

zero_address(A) :- atom(A), ( A == zero_address ; sub_atom(A, _, _, _, 'zero address') ; A == 'address(0)' ), !.

node_type(N, T) :- ( s_type(N, T0) -> T = T0 ; T = uint256 ).

var_node(Id, '$VAR'(K), var(Id, K)).

clause_edges(Kind, Id, T, _Src) :-
	(   Kind == initial
	->  forall(member(F, T), fluent_slots(Id, F))
	;   Kind == observe
	->  T = observe(Es, _),
	    forall(member(E, Es), action_slots(Id, E))
	;   Kind == timeless
	->  T = l_timeless(H, _),
	    ( callable(H) -> functor(H, F, N), term_slots(Id, tl(F/N), H) ; true )
	;   memberchk(Kind, [initiated, terminated])
	->  T =.. [_, Ev, Fl, Cond],
	    event_slots(Id, Ev), fluent_slots(Id, Fl), conds_edges(Id, Cond)
	;   Kind == updated
	->  T = updated(Ev, Fl, Old-New, Cond),
	    event_slots(Id, Ev), fluent_slots(Id, Fl), conds_edges(Id, Cond),
	    link(Id, Old, New)
	;   Kind == d_pre
	->  T = d_pre(Cond), conds_edges(Id, Cond)
	;   true
	).

event_slots(Id, happens(E, _, _)) :- !, action_slots(Id, E).
event_slots(_, _).

action_slots(Id, E) :- callable(E), !, functor(E, F, N), term_slots(Id, ac(F/N), E).
action_slots(_, _).

fluent_slots(Id, F) :- callable(F), F \= not(_), !, functor(F, Fn, N), term_slots(Id, fl(Fn/N), F).
fluent_slots(Id, not(F)) :- !, fluent_slots(Id, F).
fluent_slots(_, _).

term_slots(Id, K, T) :-
	T =.. [_|Args],
	forall(nth1(I, Args, A), node_link(Id, A, slot(K, I))).

node_link(Id, A, Node) :-
	(   A = '$VAR'(_)
	->  var_node(Id, A, V), assertz(s_edge(V, Node))
	;   seed_of(A, S)
	->  assertz(s_seed(Node, S)),
	    ( integer(A), A < 0 -> assertz(s_seed(Node, neg)) ; true )
	;   compound(A), A =.. [Op|_], arith_op(Op)
	->  assertz(s_seed(Node, num)),
	    forall(( sub_term(V0, A), V0 = '$VAR'(_) ), ( var_node(Id, V0, VN), assertz(s_seed(VN, num)) ))
	;   true
	).

seed_of(A, num) :- integer(A), !.
seed_of(A, flt) :- float(A), !.
seed_of(A, flt) :- rational(A), \+ integer(A), !.
seed_of(A, str) :- string(A), !.
seed_of(A, sym(A)) :- atom(A), A \== [], !.

link(Id, A, B) :-
	(   A = '$VAR'(_)
	->  var_node(Id, A, NA), node_link(Id, B, NA)
	;   B = '$VAR'(_)
	->  var_node(Id, B, NB), node_link(Id, A, NB)
	;   true
	).

conds_edges(Id, Cond) :- forall(member(C, Cond), cond_edges(Id, C)).

cond_edges(Id, happens(not(E), _, _)) :- !, action_slots(Id, E).
cond_edges(Id, happens(E, _, _)) :- !, action_slots(Id, E).
cond_edges(Id, holds(F, _)) :- !, fluent_slots(Id, F).
cond_edges(Id, not(G)) :- !, cond_edges(Id, G).
cond_edges(Id, \+ G) :- !, cond_edges(Id, G).
cond_edges(Id, X is E) :- !,
	num_seed(Id, X),
	forall(( sub_term(V, E), ( V = '$VAR'(_) ; number(V) ) ), num_seed(Id, V)),
	(   sub_term(S, E), compound(S), S \= '$VAR'(_), S =.. [Op|_], \+ arith_op(Op)
	->  (   Op == (/)
	    ->  problem(non_integer, unknown, 'division with / can give a fraction, and the EVM has integers only: write // (integer division) if that is what is meant.', [])
	    ;   problem(arithmetic, unknown, 'arithmetic the EVM does not have: ~w', [Op])
	    )
	;   true
	).
cond_edges(Id, C) :-
	C =.. [Op, A, B], memberchk(Op, [<, >, =<, >=, =:=, =\=]), !,
	link(Id, A, B), num_seed(Id, A), num_seed(Id, B).
cond_edges(Id, C) :-
	C =.. [Op, A, B], memberchk(Op, [=, \=, ==, \==]), !,
	link(Id, A, B).
cond_edges(Id, G) :-
	callable(G), functor(G, F, N),
	(   s_clause(_, timeless, l_timeless(H, _), _, _), functor(H, F, N)
	->  term_slots(Id, tl(F/N), G)
	;   true
	).

num_seed(Id, X) :-
	(   X = '$VAR'(_) -> var_node(Id, X, N), assertz(s_seed(N, num))
	;   float(X) -> var_node(Id, '$VAR'(float), N), assertz(s_seed(N, flt))
	;   true
	).

arith_op(+). arith_op(-). arith_op(*). arith_op(//). arith_op(mod).
arith_op(min). arith_op(max). arith_op('$VAR').

		 /*******************************
		 *	   the fluents' shapes	*
		 *******************************/

%	s_fluent(F/N, Shape, ValuePos): Shape is bool (N = 0), functional
%	(ValuePos the value, the others keys) or set.
classify_fluents :-
	findall(F/N, ( s_clause(_, Kind, T, _, _), clause_fluent(Kind, T, Fl),
		       callable(Fl), functor(Fl, F, N) ), FNs0),
	sort(FNs0, FNs),
	forall(member(FN, FNs), classify_fluent(FN)).

clause_fluent(initial, L, F) :- member(F, L).
clause_fluent(initiated, initiated(_, F, _), F).
clause_fluent(terminated, terminated(_, F, _), F).
clause_fluent(updated, updated(_, F, _, _), F).
clause_fluent(Kind, T, F) :-
	memberchk(Kind, [initiated, terminated, updated, d_pre]),
	sub_term(holds(F0, _), T), ( F0 = not(F) -> true ; F = F0 ).

classify_fluent(F/0) :- !, assertz(s_fluent(F/0, bool, 0)).
%	A fluent with a default is a function of its other arguments by
%	declaration, and its value is the last one.
classify_fluent(F/N) :-
	s_default(F/N, _), !,
	assertz(s_fluent(F/N, functional, N)).
classify_fluent(F/N) :-
	findall(Pos, ( s_clause(_, updated, updated(_, Fl, Old-_, _), _, _),
		       functor(Fl, F, N), arg(Pos, Fl, A), A == Old ), Ps0),
	sort(Ps0, Ps),
	(   Ps = [VP] -> true
	;   Ps = [] -> VP = N
	;   VP = N, problem(update_positions, unknown,
			   'the fluent ~w/~w is updated at more than one position: it has no one value.', [F, N])
	),
	(   Ps \== [] -> Shape = functional
	;   functional_evidence(F/N, VP) -> Shape = functional
	;   Shape = set
	),
	(   Shape == functional, \+ initial_functional(F/N, VP)
	->  problem(two_values, unknown, 'the initial state gives ~w/~w two values for one key.', [F, N])
	;   true
	),
	(   Shape == functional
	->  forall(( s_clause(_, initiated, initiated(Ev, Fl, Cond), Src, _), functor(Fl, F, N) ),
		   (   guarded_initiation(Ev, Fl, Cond, VP) -> true
		   ;   problem(two_values, Src,
			       'this law can give ~w/~w a second value beside the one it has (guard it with the key''s absence, or terminate the old value in the same action).',
			       [F, N])
		   ))
	;   true
	),
	assertz(s_fluent(F/N, Shape, VP)).

%	A fluent with no updates is a function when it is initiated at all and
%	every initiation is guarded — or when it is only ever set by the initial
%	state with one value per key, and read with its value unbound.
functional_evidence(F/N, VP) :-
	functor(Fl0, F, N),
	(   s_clause(_, initiated, initiated(_, Fl0, _), _, _)
	->  forall(( s_clause(_, initiated, initiated(Ev, Fl, Cond), _, _), functor(Fl, F, N) ),
		   guarded_initiation(Ev, Fl, Cond, VP))
	;   s_clause(_, initial, L, _, _), member(Fl1, L), functor(Fl1, F, N)
	->  initial_functional(F/N, VP),
	    \+ ( s_clause(_, terminated, terminated(_, Fl2, _), _, _), functor(Fl2, F, N) )
	).

initial_functional(F/N, VP) :-
	findall(Keys-V, ( s_clause(_, initial, L, _, _), member(Fl, L), functor(Fl, F, N),
			  key_value(Fl, VP, Keys, V) ), KVs),
	\+ ( member(K-V1, KVs), member(K-V2, KVs), V1 \== V2 ).

key_value(Fl, VP, Keys, V) :-
	Fl =.. [_|Args], nth1(VP, Args, V, Keys).

guarded_initiation(Ev, Fl, Cond, VP) :-
	key_value(Fl, VP, Keys, _),
	functor(Fl, F, N),
	(   member(holds(not(G), _), Cond), functor(G, F, N),
	    key_value(G, VP, Keys1, GV), Keys1 == Keys, GV = '$VAR'(_),
	    \+ occurs_elsewhere(GV, Fl-Cond, 1)
	->  true
	;   %  a termination in the same action that clears the key
	    s_clause(_, terminated, terminated(Ev2, Fl2, Cond2), _, _),
	    functor(Fl2, F, N),
	    same_event(Ev, Ev2, Map),
	    key_value(Fl2, VP, Keys2, TV), TV = '$VAR'(_),
	    maplist(mapped(Map), Keys2, Keys2m), Keys2m == Keys,
	    clearing_conditions(Cond2, Fl2)
	).

occurs_elsewhere(V, T, Max) :-
	findall(x, ( sub_term(S, T), S == V ), Xs), length(Xs, K), K > Max.

%	Two event patterns of the same action, with the map from the second's
%	variables to the first's arguments (both numbervar'd in their own clause).
same_event(happens(E1, _, _), happens(E2, _, _), Map) :-
	functor(E1, F, N), functor(E2, F, N),
	E1 =.. [_|A1], E2 =.. [_|A2],
	pairs_keys_values(Map0, A2, A1),
	include([K-_]>>(K = '$VAR'(_)), Map0, Map),
	\+ ( member(K-_, Map0), K \= '$VAR'(_) ).

mapped(Map, T, U) :- ( memberchk(T-U0, Map) -> U = U0 ; U = none(T) ).

%	The conditions of a termination that clears whatever value is there:
%	none, or only the read of the fact being terminated.
clearing_conditions([], _).
clearing_conditions([holds(G, _)], Fl) :- G == Fl.

		 /*******************************
		 *	  clause-level checks	*
		 *******************************/

check_clauses :-
	forall(s_clause(_, d_pre, d_pre(Cond), Src, _), check_d_pre(Cond, Src)),
	forall(( s_clause(_, Kind, T, Src, _), memberchk(Kind, [initiated, terminated, updated]) ),
	       check_law(T, Src)),
	forall(( s_clause(Id, Kind, T, Src, _), memberchk(Kind, [initiated, terminated, updated, d_pre]) ),
	       check_calls(Id, T, Src)),
	forall(( s_clause(_, observe, observe(Es, _), Src, _), member(E, Es), callable(E),
		 functor(E, F, N), \+ s_action(F/N) ),
	       problem(environment_event, Src, 'the observation ~w is not an action anyone calls.', [short(E)])).

check_d_pre(Cond, Src) :-
	include([happens(_, _, _)]>>true, Cond, Hs),
	length(Hs, NH),
	(   NH > 1
	->  problem(concurrency, Src, 'a constraint over two actions happening together: a contract sees one call at a time.', [])
	;   NH =:= 1, Hs = [happens(E, _, _)], \+ ( callable(E), functor(E, F, N), s_action(F/N) )
	->  problem(environment_event, Src, 'a constraint on ~w, which is not an action anyone calls.', [short(E)])
	;   NH =:= 1, Hs = [happens(_, T1, T2)],
	    member(holds(_, T), Cond), T \== T1, T \== T2
	->  problem(timed_constraint, Src, 'a constraint about a state other than just before or just after the call.', [])
	;   NH =:= 1, Hs = [happens(_, T1, T2)],
	    member(holds(_, Ta), Cond), Ta == T1, member(holds(_, Tb), Cond), Tb == T2
	->  problem(mixed_constraint, Src, 'a constraint that reads the state both before and after the call: write it as two constraints.', [])
	;   true
	).

check_law(T, Src) :-
	T =.. [_, happens(E, T1, _), _|Rest],
	last(Rest, Cond),
	(   \+ ( callable(E), functor(E, F, N), s_action(F/N) )
	->  true		% reported with the event
	;   member(holds(_, Tm), Cond), Tm \== T1
	->  problem(timed_law, Src, 'a causal law whose conditions read a state other than the one before the action.', [])
	;   true
	).

%	Calls in conditions that are neither fluents, comparisons, arithmetic,
%	nor ground timeless facts.
check_calls(_Id, T, Src) :-
	( T = d_pre(Cond) -> true ; T =.. L, last(L, Cond) ),
	forall(member(C, Cond), check_call(C, Src)).

check_call(happens(_, _, _), _) :- !.
check_call(holds(_, _), _) :- !.
check_call(_ is _, _) :- !.
check_call(C, _) :- C =.. [Op, _, _], memberchk(Op, [<, >, =<, >=, =:=, =\=, =, \=, ==, \==]), !.
check_call(not(G), Src) :- !, check_call(G, Src).
check_call(\+ G, Src) :- !, check_call(G, Src).
check_call(G, Src) :-
	(   callable(G), functor(G, F, N), functor(H, F, N),
	    s_clause(_, timeless, l_timeless(H, _), _, _)
	->  true
	;   problem(prolog, Src, 'a condition calls ~w, which is Prolog, not state the contract holds.', [short(G)])
	).

		 /*******************************
		 *	      names		*
		 *******************************/

reserved(W) :- memberchk(W, [
	abstract, after, alias, apply, auto, byte, case, catch, copyof, default,
	define, final, immutable, implements, in, inline, let, macro, match,
	mutable, null, of, override, partial, promise, reference, relocatable,
	sealed, sizeof, static, supports, switch, typedef, typeof, unchecked,
	var, address, anonymous, as, assembly, bool, break, bytes, calldata,
	constant, constructor, continue, contract, delete, do, else, emit, enum,
	error, event, external, fallback, false, for, from, function, if, import,
	indexed, interface, internal, is, library, mapping, memory, modifier,
	new, payable, pragma, private, public, pure, receive, return, returns,
	revert, storage, string, struct, true, try, type, using, view, virtual,
	while, int, uint, fixed, ufixed, days, ether, wei, gwei, seconds,
	minutes, hours, weeks, years, this, super, selfdestruct, now, msg,
	block, tx, abi, require, assert, keccak256, sha256, gasleft, balance_]).

%	lower camel case from an atom, dropping a leading article
camel(A, Name) :-
	atom_codes(A, Cs0),
	maplist([C, D]>>( code_type(C, alnum) -> D = C ; D = 0'_ ), Cs0, Cs1),
	atom_codes(A1, Cs1),
	atomic_list_concat(Ws0, '_', A1),
	exclude(==(''), Ws0, Ws1),
	( Ws1 = [the, _|_] -> Ws1 = [_|Ws] ; Ws = Ws1 ),
	(   Ws = [W0|Wr]
	->  downcase_atom(W0, L0),
	    maplist(cap, Wr, Cr),
	    atomic_list_concat([L0|Cr], N0)
	;   N0 = x
	),
	( atom_codes(N0, [C0|_]), code_type(C0, digit) -> atom_concat(x, N0, Name) ; Name = N0 ).

pascal(A, Name) :- camel(A, C), cap(C, Name).

cap(W, C) :-
	atom_codes(W, [F|R]), !,
	code_type(F, to_lower(U)), atom_codes(C, [U|R]).
cap(W, W).

%	An identifier, unique across the contract. Key identifies what it names.
issue_name(Key, Want, Name) :-
	(   s_name(Key, N0) -> Name = N0
	;   fresh_name(Want, 1, Name), assertz(s_name(Key, Name))
	).

fresh_name(Want, I, Name) :-
	( I =:= 1 -> N0 = Want ; atom_concat(Want, I, N0) ),
	(   ( reserved(N0) ; s_name(_, N0) )
	->  I1 is I + 1,
	    ( reserved(N0), I =:= 1 -> atom_concat(Want, '_', W1), fresh_name(W1, 1, Name) ; fresh_name(Want, I1, Name) )
	;   Name = N0
	).

fluent_name(F/N, Name) :- camel(F, W), issue_name(fluent(F/N), W, Name).
presence_name(F/N, Name) :-
	pascal(F, P), atom_concat(has, P, W), issue_name(has(F/N), W, Name).
action_name(A/N, Name) :- camel(A, W), issue_name(action(A/N), W, Name).
event_name(A/N, Name) :- pascal(A, W), issue_name(event(A/N), W, Name).
account_name(Atom, Name) :-
	(   s_account(Atom, Name) -> true
	;   camel(Atom, W0), ( atom_concat(the, _, W0) -> W = W0 ; W = W0 ),
	    account_want(Atom, W, W1),
	    issue_name(account(Atom), W1, Name), assertz(s_account(Atom, Name))
	).

%	'the owner' reads better as theOwner than owner, and owner is usually
%	also a fluent: keep the article in account names.
account_want(Atom, _, W) :-
	atomic_list_concat(Ws, ' ', Atom), Ws = [the, _|_], !,
	atomic_list_concat(Ws, '_', A1), camel_keep(A1, W).
account_want(_, W, W).

camel_keep(A, Name) :-
	atomic_list_concat([W0|Wr], '_', A),
	maplist(cap, Wr, Cr), atomic_list_concat([W0|Cr], Name).

symbol_name(Atom, Name) :-
	(   s_symbol(Atom, Name) -> true
	;   camel(Atom, C), upcase_atom(C, U), issue_name(symbol(Atom), U, Name),
	    assertz(s_symbol(Atom, Name))
	).

		 /*******************************
		 *	    generation		*
		 *******************************/

generate(P, Options, Text, Contract) :-
	contract_name(P, Options, Contract),
	option(templates(Ts), Options, []),
	( option(source(Src), Options) -> split_string(Src, "\n", "", Lines) ; Lines = [] ),
	b_setval(lps_sol_lines, Lines),
	b_setval(lps_sol_templates, Ts),
	b_setval(lps_sol_in_function, false),
	b_setval(lps_sol_in_ctor, false),
	%  names, in a fixed order so a program always gives the same contract
	forall(s_fluent(FN, _, _), fluent_name(FN, _)),
	forall(( s_fluent(FN, functional, _), \+ s_default(FN, _) ), presence_name(FN, _)),
	forall(s_action(AN), action_name(AN, _)),
	forall(s_action(AN), event_name(AN, _)),
	residue_notes(Lines, Options),
	findall(fn(AN, Code), ( s_action(AN),
				( action_code(AN, Code) -> true
				; AN = A/N, problem(internal, unknown, 'the action ~w/~w could not be translated.', [A, N]), fail ) ),
		Fns),
	invariant_code(Inv),
	b_setval(lps_sol_in_function, true),
	findall(TL, ( s_name(timeless(TF), HN), with_output_to(string(TL), write_timeless(TF, HN)) ), TLs),
	b_setval(lps_sol_in_function, false),
	constructor_code(Ctor),
	with_output_to(string(Text),
		       write_contract(P, Options, Contract, Fns, Inv, Ctor, TLs)).

%	A migrated document can keep source fragments no rule translated, as
%	`% RESIDUE <id> BEGIN` comment blocks (LE2's le_writer.pl): they are not
%	in the program, so they are not in the contract either — said, not hidden.
residue_notes(Lines, Options) :-
	option(origin(O), Options, buffer),
	forall(( nth1(L, Lines, S), sub_string(S, _, _, _, "% RESIDUE "), sub_string(S, _, _, _, " BEGIN") ),
	       note(residue, src(O, L, 0, le),
		    'an untranslated source fragment (a RESIDUE block) is kept here as a comment: it is not in the program, and not in the contract.', [])).

contract_name(_, Options, Name) :-
	option(contract(N0), Options), !, pascal(N0, Name).
contract_name(_, Options, Name) :-
	option(origin(O), Options), atom(O), O \== '', !,
	file_base_name(O, B), file_name_extension(S, _, B), pascal(S, Name).
contract_name(_, _, 'Program').

		 /*******************************
		 *     expressions (Solidity)	*
		 *******************************/

/*  A context maps the clause's variables ('$VAR'(K)) to Solidity expressions,
    with the clause id for their types. `cond_exprs/5` compiles a list of
    conditions to a list of Solidity boolean expressions, binding the
    variables its reads define; the literals are scheduled so that a read
    binds a variable before a comparison uses it. */

ctx_new(Id, ctx(Id, B, [])) :- empty_assoc(B).
ctx_bind(ctx(Id, B0, R), K, E, ctx(Id, B, R)) :- put_assoc(K, B0, E, B).
ctx_get(ctx(_, B, _), K, E) :- get_assoc(K, B, E).
ctx_id(ctx(Id, _, _), Id).

%	A variable whose value was read from storage (directly, or computed from
%	one that was): the values a law's writes need snapshotted.
ctx_bind_read(ctx(Id, B0, R), K, E, ctx(Id, B, [K|R])) :- put_assoc(K, B0, E, B).
ctx_read(ctx(_, _, R), K) :- memberchk(K, R).
ctx_reads_in(Ctx, T) :- sub_term(V, T), V = '$VAR'(K), ctx_read(Ctx, K), !.

bound(Ctx, T) :-
	\+ ( sub_term(V, T), V = '$VAR'(K), \+ ctx_get(Ctx, K, _) ).

term_type(Ctx, T, Type) :-
	(   T = '$VAR'(_) -> ctx_id(Ctx, Id), var_node(Id, T, N), node_type(N, Type)
	;   integer(T) -> ( T < 0 -> Type = int256 ; Type = uint256 )
	;   string(T) -> Type = string
	;   atom(T), zero_address(T) -> Type = address
	;   atom(T) -> Type = symbol
	;   compound(T) -> Type = uint256
	;   Type = uint256
	).

%	sx(+Ctx, +Term, +Type, -Solidity)
sx(Ctx, '$VAR'(K), _, E) :- !,
	(   ctx_get(Ctx, K, E) -> true
	;   throw(unbound_variable(K))
	).
sx(_, N, _, E) :- integer(N), !,
	(   N =:= 2^256 - 1 -> E = 'type(uint256).max'
	;   format(atom(E), '~d', [N])
	).
sx(_, S, _, E) :- string(S), !, solidity_string(S, E).
sx(_, A, Type, E) :- atom(A), !, constant(A, Type, E).
sx(Ctx, T, _, E) :-
	compound(T), T =.. [Op, X, Y], sol_binop(Op, SOp), !,
	sx(Ctx, X, uint256, EX), sx(Ctx, Y, uint256, EY),
	format(atom(E), '(~w ~w ~w)', [EX, SOp, EY]).
sx(Ctx, T, _, E) :-
	compound(T), T =.. [Op, X, Y], memberchk(Op, [min, max]), !,
	assert_helper(Op),
	sx(Ctx, X, uint256, EX), sx(Ctx, Y, uint256, EY),
	format(atom(E), '_~w(~w, ~w)', [Op, EX, EY]).
sx(_, T, _, _) :-
	throw(cannot_write(T)).

sol_binop(+, +). sol_binop(-, -). sol_binop(*, *). sol_binop(//, /). sol_binop(mod, '%').

assert_helper(H) :- ( s_helper(H) -> true ; assertz(s_helper(H)) ).

constant(A, Type, E) :-
	(   zero_address(A) -> E = 'address(0)'
	;   Type == address
	->  account_name(A, N0),
	    (   b_getval(lps_sol_in_ctor, true) -> atom_concat(N0, '_', E)
	    ;   E = N0, note_account_use(A)
	    )
	;   Type == string -> atom_string(A, S), solidity_string(S, E)
	;   Type == bool -> E = A
	;   symbol_name(A, E)
	).

note_account_use(A) :-
	(   b_getval(lps_sol_in_function, true), \+ s_account_used(A)
	->  assertz(s_account_used(A))
	;   true
	).

%	Solidity's plain string literals are ASCII; anything else is unicode"…".
solidity_string(S, E) :-
	string_codes(S, Cs),
	foldl(esc, Cs, Out, []),
	string_codes(Body, Out),
	(   member(C, Cs), C > 127
	->  format(atom(E), 'unicode"~s"', [Body])
	;   format(atom(E), '"~s"', [Body])
	).

%	Comments are kept ASCII: the sandbox receives the contract as base64 in
%	its address, and a page decoding that as Latin-1 would garble the rest.
ascii_text(T0, T) :-
	atom_codes(T0, Cs0),
	foldl(ascii_code, Cs0, Cs, []),
	atom_codes(T, Cs).

ascii_code(C, [C|T], T) :- C < 128, !.
ascii_code(C, Out, T) :- ascii_for(C, A), !, atom_codes(A, Cs), append(Cs, T, Out).
ascii_code(_, [0'?|T], T).

ascii_for(0x2014, '--'). ascii_for(0x2013, '-'). ascii_for(0x2026, '...').
ascii_for(0x2018, ''''). ascii_for(0x2019, ''''). ascii_for(0x201C, '"'). ascii_for(0x201D, '"').
ascii_for(0x25B8, '>'). ascii_for(0x2192, '->'). ascii_for(0x00A0, ' '). ascii_for(0x2264, '<=').
ascii_for(0x2265, '>='). ascii_for(0x2260, '!='). ascii_for(0x00D7, 'x').
ascii_for(C, A) :- C >= 0xC0, C =< 0x17F, char_code(Ch, C), accentless(Ch, A).

accentless(Ch, A) :-
	atom_codes(Ch, [C]),
	(   memberchk(C-A0, [0xE0-a, 0xE1-a, 0xE2-a, 0xE3-a, 0xE4-a, 0xE7-c, 0xE8-e, 0xE9-e, 0xEA-e,
			       0xED-i, 0xF3-o, 0xF4-o, 0xF5-o, 0xF6-o, 0xFA-u, 0xFC-u, 0xF1-n,
			       0xC0-'A', 0xC1-'A', 0xC7-'C', 0xC9-'E', 0xD3-'O', 0xDA-'U'])
	->  A = A0
	;   A = '?'
	).

esc(0'", ["\\", 0'"|T], T) :- !.
esc(0'\\, ["\\", 0'\\|T], T) :- !.
esc(0'\n, ["\\", 0'n|T], T) :- !.
esc(C, [C|T], T).

%	equality, with strings compared by hash
eq_expr(Ctx, A, B, Neg, E) :-
	term_type(Ctx, A, TA0), term_type(Ctx, B, TB0),
	pick_type(TA0, TB0, T),
	sx(Ctx, A, T, EA), sx(Ctx, B, T, EB),
	( Neg == true -> Op = '!=' ; Op = '==' ),
	(   T == string
	->  format(atom(E), 'keccak256(bytes(~w)) ~w keccak256(bytes(~w))', [EA, Op, EB])
	;   format(atom(E), '~w ~w ~w', [EA, Op, EB])
	).

pick_type(symbol, T, T) :- T \== symbol, !.
pick_type(T, _, T).

%	Fluent access: the storage expression of a fluent's value (functional),
%	its presence, or its membership (set / bool).
fluent_store(Ctx, Fl, Shape, VP, Value, Presence) :-
	functor(Fl, F, N), Fl =.. [_|Args],
	fluent_name(F/N, Name),
	(   Shape == bool
	->  Value = Name, Presence = Name
	;   Shape == set
	->  keys_expr(Ctx, F/N, Args, 1, Idx), atom_concat(Name, Idx, Value), Presence = Value
	;   nth1(VP, Args, _, Keys),
	    positions_except(N, VP, KPs),
	    keys_expr_at(Ctx, F/N, Keys, KPs, Idx),
	    atom_concat(Name, Idx, Value),
	    (   s_default(F/N, _)
	    ->  Presence = true             % every key has a value: its default
	    ;   presence_name(F/N, HN), atom_concat(HN, Idx, Presence)
	    )
	).

positions_except(N, VP, Ps) :- numlist_(1, N, All), exclude(==(VP), All, Ps).
numlist_(L, H, Ns) :- ( L > H -> Ns = [] ; numlist(L, H, Ns) ).

keys_expr(Ctx, FN, Args, _, Idx) :-
	length(Args, N), numlist_(1, N, Ps), keys_expr_at(Ctx, FN, Args, Ps, Idx).

keys_expr_at(_, _, [], [], '') :- !.
keys_expr_at(Ctx, FN, [A|As], [P|Ps], Idx) :-
	node_type(slot(fl(FN), P), T),
	sx(Ctx, A, T, E),
	keys_expr_at(Ctx, FN, As, Ps, Rest),
	format(atom(Idx), '[~w]~w', [E, Rest]).

%!	cond_exprs(+Conds, +Ctx0, -Ctx, -Exprs) is det.
cond_exprs(Conds, Ctx0, Ctx, Exprs) :-
	schedule(Conds, Ctx0, Ctx, Exprs).

schedule([], Ctx, Ctx, []) :- !.
schedule(Conds, Ctx0, Ctx, Exprs) :-
	(   select(C, Conds, Rest), ready(Ctx0, C)
	->  lit(C, Ctx0, Ctx1, E1),
	    schedule(Rest, Ctx1, Ctx, E2),
	    append(E1, E2, Exprs)
	;   Conds = [C|_],
	    throw(unschedulable(C))
	).

%	A literal can be compiled once its inputs are bound.
ready(_, happens(_, _, _)).
ready(Ctx, holds(not(Fl), _)) :- !, fluent_inputs_bound(Ctx, Fl, not).
ready(Ctx, holds(Fl, _)) :- fluent_inputs_bound(Ctx, Fl, pos).
ready(Ctx, X is E) :- bound(Ctx, E), ( X = '$VAR'(_) ; true ).
ready(Ctx, A = B) :- ( bound(Ctx, A) ; bound(Ctx, B) ), !.
ready(Ctx, C) :- C =.. [Op, A, B], memberchk(Op, [<, >, =<, >=, =:=, =\=, \=, ==, \==]), bound(Ctx, A), bound(Ctx, B).
ready(Ctx, not(G)) :- bound(Ctx, G).
ready(Ctx, \+ G) :- bound(Ctx, G).
ready(_, G) :- constant_goal(G, _), !.
ready(Ctx, G) :- callable(G), \+ memberchk(G, [holds(_, _)]), bound(Ctx, G).

fluent_inputs_bound(Ctx, Fl, Pol) :-
	functor(Fl, F, N), s_fluent(F/N, Shape, VP),
	(   Shape == bool -> true
	;   Shape == set -> bound(Ctx, Fl)
	;   Fl =.. [_|Args], nth1(VP, Args, V, Keys),
	    bound(Ctx, Keys),
	    ( Pol == pos -> true ; ( bound(Ctx, V) ; true ) )
	).

lit(happens(_, _, _), Ctx, Ctx, []) :- !.
lit(holds(not(Fl), _), Ctx, Ctx, [E]) :- !,
	functor(Fl, F, N), s_fluent(F/N, Shape, VP),
	fluent_store(Ctx, Fl, Shape, VP, Value, Presence),
	(   Shape \== functional
	->  format(atom(E), '!~w', [Presence])
	;   Fl =.. [_|Args], nth1(VP, Args, V),
	    (   V = '$VAR'(K), \+ ctx_get(Ctx, K, _)
	    ->  ( Presence == true -> E = false ; format(atom(E), '!~w', [Presence]) )
	    ;   node_type(slot(fl(F/N), VP), T), sx(Ctx, V, T, EV),
		(   T == string
		->  format(atom(Eq), 'keccak256(bytes(~w)) == keccak256(bytes(~w))', [Value, EV])
		;   format(atom(Eq), '~w == ~w', [Value, EV])
		),
		(   Presence == true -> format(atom(E), '!(~w)', [Eq])
		;   format(atom(E), '!(~w && ~w)', [Presence, Eq])
		)
	    )
	).
lit(holds(Fl, _), Ctx0, Ctx, Es) :- !,
	functor(Fl, F, N), s_fluent(F/N, Shape, VP),
	fluent_store(Ctx0, Fl, Shape, VP, Value, Presence),
	(   Shape \== functional
	->  Ctx = Ctx0, Es = [Presence]
	;   Fl =.. [_|Args], nth1(VP, Args, V),
	    ( Presence == true -> Ps = [] ; Ps = [Presence] ),
	    (   V = '$VAR'(K), \+ ctx_get(Ctx0, K, _)
	    ->  ctx_bind_read(Ctx0, K, Value, Ctx), Es = Ps
	    ;   Ctx = Ctx0,
		node_type(slot(fl(F/N), VP), T), sx(Ctx0, V, T, EV),
		( T == string
		-> format(atom(E2), 'keccak256(bytes(~w)) == keccak256(bytes(~w))', [Value, EV])
		;  format(atom(E2), '~w == ~w', [Value, EV]) ),
		append(Ps, [E2], Es)
	    )
	).
lit('$VAR'(K) is E, Ctx0, Ctx, []) :- \+ ctx_get(Ctx0, K, _), !,
	sx(Ctx0, E, uint256, SE),
	bind_derived(Ctx0, K, SE, E, Ctx).
lit(X is E, Ctx, Ctx, [C]) :- !,
	sx(Ctx, X, uint256, SX), sx(Ctx, E, uint256, SE),
	format(atom(C), '~w == ~w', [SX, SE]).
lit(A = B, Ctx0, Ctx, Es) :- !,
	(   A = '$VAR'(K), \+ ctx_get(Ctx0, K, _)
	->  term_type(Ctx0, A, T), sx(Ctx0, B, T, E), bind_derived(Ctx0, K, E, B, Ctx), Es = []
	;   B = '$VAR'(K), \+ ctx_get(Ctx0, K, _)
	->  term_type(Ctx0, B, T), sx(Ctx0, A, T, E), bind_derived(Ctx0, K, E, A, Ctx), Es = []
	;   Ctx = Ctx0, eq_expr(Ctx0, A, B, false, E), Es = [E]
	).
lit(C, Ctx, Ctx, [E]) :-
	C =.. [Op, A, B], memberchk(Op, [==, =:=]), !, eq_expr(Ctx, A, B, false, E).
lit(C, Ctx, Ctx, [E]) :-
	C =.. [Op, A, B], memberchk(Op, [\=, \==, =\=]), !, eq_expr(Ctx, A, B, true, E).
lit(C, Ctx, Ctx, [E]) :-
	C =.. [Op, A, B], cmp_op(Op, SOp), !,
	sx(Ctx, A, uint256, EA), sx(Ctx, B, uint256, EB),
	format(atom(E), '~w ~w ~w', [EA, SOp, EB]).
lit(not(G), Ctx, Ctx, [E]) :- !, lit(G, Ctx, _, Es), conj(Es, C), format(atom(E), '!(~w)', [C]).
lit(\+ G, Ctx, Ctx, [E]) :- !, lit(not(G), Ctx, _, [E]).
%	a named constant: its name, bound to the variable that reads it
lit(G, Ctx0, Ctx, Es) :-
	constant_goal(G, Name), !,
	arg(1, G, V),
	(   V = '$VAR'(K), \+ ctx_get(Ctx0, K, _)
	->  ctx_bind(Ctx0, K, Name, Ctx), Es = []
	;   Ctx = Ctx0, sx(Ctx0, V, uint256, EV), format(atom(E), '~w == ~w', [EV, Name]), Es = [E]
	).
lit(G, Ctx, Ctx, [E]) :-
	%  a ground timeless fact table, looked up
	functor(G, F, N), G =.. [_|Args],
	timeless_helper(F/N, HName),
	findall(SA, ( nth1(I, Args, A), node_type(slot(tl(F/N), I), T), sx(Ctx, A, T, SA) ), SAs),
	atomic_list_concat(SAs, ', ', AL),
	format(atom(E), '~w(~w)', [HName, AL]).

bind_derived(Ctx0, K, SE, E, Ctx) :-
	(   ctx_reads_in(Ctx0, E) -> ctx_bind_read(Ctx0, K, SE, Ctx) ; ctx_bind(Ctx0, K, SE, Ctx) ).

cmp_op(<, <). cmp_op(>, >). cmp_op(=<, '<='). cmp_op(>=, '>=').

conj([], true) :- !.
conj(Es, C) :- atomic_list_concat(Es, ' && ', C).

timeless_helper(F/N, Name) :-
	pascal(F, P), atom_concat('_is', P, W), issue_name(timeless(F/N), W, Name).

		 /*******************************
		 *	    the functions	*
		 *******************************/

%!	action_code(+A/N, -Code) is det.
%
%	Code = fn(Name, Params, Body, EventArgs, Comment): Params a list of
%	Type-Name, Body a list of lines.
action_code(A/N, fn(Name, Params, Body, EvArgs, Comment)) :-
	action_name(A/N, Name),
	b_setval(lps_sol_in_function, true),
	params(A/N, Params, ArgExprs),
	action_template(A/N, Comment),
	%  the constraints on this action, in source order
	findall(c(Id, Cond, Src), ( s_clause(Id, d_pre, d_pre(Cond), Src, _),
				    member(happens(E, _, _), Cond), callable(E), functor(E, A, N) ), Cs),
	partition([c(_, Cond, _)]>>( member(happens(_, _, T2), Cond),
				     member(holds(_, T), Cond), T == T2 ), Cs, PostCs, PreCs),
	foldl(constraint_lines(A/N, ArgExprs), PreCs, PreLines, []),
	%  the laws of this action
	findall(l(Kind, Id, T, Src), ( member(Kind, [terminated, initiated, updated]),
				       s_clause(Id, Kind, T, Src, _),
				       T =.. [_, happens(E2, _, _)|_], callable(E2), functor(E2, A, N) ), Ls),
	length(Ls, NLaws),
	( NLaws > 6 -> b_setval(lps_sol_law_array, true) ; b_setval(lps_sol_law_array, false) ),
	b_setval(lps_sol_law_count, 0),
	foldl(law_top(ArgExprs), Ls, LawTops, []),
	b_getval(lps_sol_law_count, NGuards),
	(   NGuards > 0
	->  format(atom(ArrDecl), 'bool[~d] memory law;', [NGuards]), ArrLines = [ArrDecl]
	;   ArrLines = []
	),
	law_writes(Ls, LawTops, ArgExprs, WriteLines),
	foldl(constraint_lines(A/N, ArgExprs), PostCs, PostLines, []),
	(   s_clause(_, d_pre, d_pre(IC), _, _), \+ member(happens(_, _, _), IC)
	->  InvLines = ['_checkInvariants();']
	;   InvLines = []
	),
	findall(L, ( member(t(_, Ls1, _), LawTops), member(L, Ls1) ), TopLines0),
	append(ArrLines, TopLines0, TopLines),
	ev_args(ArgExprs, EvArgs),
	event_name(A/N, EvName),
	findall(X, member(_-(_-X), EvArgs), Xs), atomic_list_concat(Xs, ', ', EvArgsText),
	format(atom(EmitL), 'emit ~w(~w);', [EvName, EvArgsText]),
	section_lines('the integrity constraints, on the state before the call', PreLines, S1),
	section_lines('the causal laws'' conditions, on the state before the call', TopLines, S2),
	section_lines('the effects, in LPS order: terminations, initiations, then updates', WriteLines, S3),
	section_lines('the integrity constraints on the state the call leaves', PostLines, S4),
	append([S1, S2, S3, S4, InvLines, [EmitL]], Body),
	b_setval(lps_sol_in_function, false).

section_lines(_, [], []) :- !.
section_lines(Title, Lines, [C|Lines]) :- format(atom(C), '// ~w', [Title]).

%	the event's arguments, as I-(T-X) with the position I of the action's
%	argument, in the interface's order (addresses first: Transfer(from, to,
%	value))
ev_args(ArgExprs, EvArgs) :-
	findall(I-(T-X), nth1(I, ArgExprs, T-X), EvArgs0),
	abi_order(EvArgs0, EvArgs).

%	The action's arguments: the caller is msg.sender, the rest parameters.
%	ArgExprs: Type-Expression per argument position, in order.
params(A/N, Params, ArgExprs) :-
	slot_names(A/N, Names),
	findall(I-Arg, ( between(1, N, I), param_for(A/N, I, Names, Arg) ), IAs),
	findall(T-X, member(_-a(T, X, _), IAs), ArgExprs),
	findall(T-X, member(_-a(T, X, param), IAs), Params0),
	abi_order(Params0, Params).

%!	abi_order(+Typed, -Ordered) is det.
%
%	Solidity's convention for a function's parameters: the addresses first,
%	then the values, each group in the sentence's order — `transfer(to,
%	value)`, `transferFrom(from, to, value)`, `approve(spender, value)`,
%	`mint(to, amount)`. The sentence reads "a sender transfers an amount to
%	a recipient"; the contract's interface is the one the standards and
%	wallets expect. (Elements are T-X or I-(T-X).)
abi_order(Ps0, Ps) :-
	partition(address_param, Ps0, As, Rest),
	append(As, Rest, Ps).

address_param(address-_) :- !.
address_param(_-(address-_)).

param_for(A/N, 1, _, a(address, 'msg.sender', caller)) :- s_caller(A/N), !.
param_for(A/N, I, Names, a(T, X, param)) :-
	node_type(slot(ac(A/N), I), T0), sol_type(T0, T),
	( nth1(I, Names, Want0), Want0 \== '' -> Want = Want0 ; type_word(T, Want) ),
	param_unique(A/N, I, Want, X).

sol_type(symbol, bytes32) :- !.
sol_type(T, T).

type_word(address, account).
type_word(uint256, amount).
type_word(int256, number).
type_word(string, text).
type_word(bytes32, name).
type_word(bool, flag).

%	parameter names are local to the function, but must not shadow a state
%	variable, a function or a keyword
param_unique(A/N, I, Want0, X) :-
	camel(Want0, Want),
	findall(W, ( between(1, N, J), J < I, s_name(param(A/N, J), W) ), Earlier),
	param_try(Want, 1, Earlier, X),
	assertz(s_name(param(A/N, I), X)).

param_try(Want, K, Earlier, X) :-
	( K =:= 1 -> X0 = Want ; atom_concat(Want, K, X0) ),
	(   ( memberchk(X0, Earlier) ; reserved(X0) ; s_name(Key, X0), Key \= param(_, _) )
	->  ( ( reserved(X0) ; s_name(Key2, X0), Key2 \= param(_, _) ), K =:= 1
	    -> atom_concat(X0, '_', X1), param_try(X1, 1, Earlier, X)
	    ;  K1 is K + 1, param_try(Want, K1, Earlier, X) )
	;   X = X0
	).

slot_names(F/N, Names) :-
	b_getval(lps_sol_templates, Ts),
	(   member(le_template(F/N, _, _, Slots, _, _), Ts)
	->  findall(W, ( between(1, N, I), I0 is I - 1,
			 ( member(slot(I0, W0), Slots) -> W = W0 ; W = '' ) ), Names)
	;   findall('', between(1, N, _), Names)
	).

%	the template's text with its placeholders' articles right ("*an owner*",
%	where the template list gives every placeholder "a")
template_comment(S, Comment) :-
	ascii_text(S, C0),
	atom_string(C0, S0),
	re_replace("\\*a ([aeiouAEIOU])"/g, "*an $1", S0, S1),
	atom_string(Comment, S1).

action_template(F/N, Comment) :-
	b_getval(lps_sol_templates, Ts),
	(   member(le_template(F/N, action, S, _, _, _), Ts) -> template_comment(S, Comment)
	;   functor(T, F, N), numbervars(T, 0, _), format(atom(Comment), '~W', [T, [numbervars(true)]])
	).

fluent_template(F/N, Comment) :-
	b_getval(lps_sol_templates, Ts),
	(   member(le_template(F/N, fluent, S, _, _, _), Ts) -> template_comment(S, Comment)
	;   functor(T, F, N), numbervars(T, 0, _), format(atom(Comment), '~W', [T, [numbervars(true)]])
	).

%	Bind an event pattern's arguments to the function's.
bind_event(happens(E, _, _), ArgExprs, Ctx0, Ctx, Conds) :-
	E =.. [_|Args],
	foldl(bind_arg, Args, ArgExprs, Ctx0-[], Ctx-Conds0),
	reverse(Conds0, Conds).

bind_arg(A, T-X, Ctx0-C0, Ctx-C) :-
	(   A = '$VAR'(K), \+ ctx_get(Ctx0, K, _)
	->  ctx_bind(Ctx0, K, X, Ctx), C = C0
	;   Ctx = Ctx0, sol_type(T, T1), sx(Ctx0, A, T1, EA),
	    ( T1 == string
	    -> format(atom(E), 'keccak256(bytes(~w)) == keccak256(bytes(~w))', [X, EA])
	    ;  format(atom(E), '~w == ~w', [X, EA]) ),
	    C = [E|C0]
	).

constraint_lines(AN, ArgExprs, c(Id, Cond, Src), Lines0, Lines) :-
	ctx_new(Id, Ctx0),
	member(happens(E, T1, T2), Cond), !,
	bind_event(happens(E, T1, T2), ArgExprs, Ctx0, Ctx1, EvConds),
	exclude([L]>>(L = happens(_, _, _)), Cond, Rest),
	guard_goal(Src,
		   ( cond_exprs(Rest, Ctx1, _, Es),
		     append(EvConds, Es, All), conj(All, C),
		     error_name(AN, Src, ErrName),
		     src_comment(Src, Comment),
		     revert_stmt(ErrName, RS),
		     format(atom(L1), 'if (~w) ~w', [C, RS]),
		     append(Comment, [L1], New) ),
		   New),
	append(New, Lines, Lines0).

%	Run a translation step; an exception is the clause's refusal, a failure
%	a refusal too (never a clause silently left out of the contract).
:- meta_predicate guard_goal(+, 0, -).
guard_goal(Src, Goal, Out) :-
	(   catch(Goal, Ex, true)
	->  (   var(Ex) -> true
	    ;   refuse_clause(Ex, Src), Out = []
	    )
	;   problem(internal, Src, 'this clause could not be translated.', []), Out = []
	).

refuse_clause(unbound_variable(_), Src) :- !,
	problem(enumeration, Src, 'a condition needs a value no argument or read supplies — finding it would mean searching a mapping, which a contract cannot do.', []).
refuse_clause(unschedulable(C), Src) :- !,
	problem(enumeration, Src, 'the condition ~w needs a value no argument or read supplies — finding it would mean searching a mapping.', [short(C)]).
refuse_clause(cannot_write(T), Src) :- !,
	problem(expression, Src, 'no Solidity for ~w.', [short(T)]).
refuse_clause(E, Src) :-
	problem(internal, Src, 'could not translate: ~q', [E]).

%	The error a constraint reverts with: the name its source comment gives
%	(`% reverts: Name`, which is how the Solidity front end marks them), or
%	<Action>Refused, numbered within the action.
%	A comment that is a sentence rather than a name (`% reverts: Ownable:
%	caller is not the owner`, a require's message) is reverted with as the
%	message it is: message(Text), no error declared.
error_name(A/N, Src, Name) :-
	src_line(Src, L),
	(   reverts_comment(L, Given)
	->  Name = Given
	;   pascal(A, PA),
	    aggregate_all(count, ( s_error(_, _, _-(A/N)) ), K0), K is K0 + 1,
	    format(atom(Name), '~wRefused~d', [PA, K])
	),
	src_text(Src, Text),
	(   Name = message(_) -> true
	;   s_error(Name, _, _) -> true
	;   assertz(s_error(Name, L, Text-(A/N)))
	).

revert_stmt(message(M), S) :- !,
	atom_string(M, MS), solidity_string(MS, E), format(atom(S), 'revert(~w);', [E]).
revert_stmt(Name, S) :- format(atom(S), 'revert ~w();', [Name]).

reverts_comment(L, Name) :-
	L > 1,
	b_getval(lps_sol_lines, Lines),
	L0 is L - 1,
	comment_lines_above(Lines, L0, Cs),
	member(C, Cs),
	sub_string(C, B, _, _, "reverts:"), !,
	B1 is B + 8, sub_string(C, B1, _, 0, R0), normalize_space(atom(R), R0),
	R \== '',
	(   atom_codes(R, [F|Cs]), code_type(F, csymf), forall(member(X, Cs), code_type(X, csym))
	->  Name = R
	;   Name = message(R)
	).

comment_lines_above(_, 0, []) :- !.
comment_lines_above(Lines, L, [S|More]) :-
	nth1(L, Lines, S0), split_string(S0, "", " \t", [S]),
	( sub_string(S, 0, _, _, "%") ; sub_string(S, 0, _, _, "//") ), !,
	L1 is L - 1, comment_lines_above(Lines, L1, More).
comment_lines_above(_, _, []).

%	The source sentence (or clause) at Src, as comment lines.
src_comment(Src, Lines) :-
	src_text(Src, T),
	src_line(Src, L),
	(   T == ''
	->  Lines = []
	;   format(atom(C), '// line ~d: ~w', [L, T]), Lines = [C]
	).

src_text(Src, Text) :-
	src_line(Src, L),
	b_getval(lps_sol_lines, Lines),
	(   L > 0, nth1(L, Lines, _)
	->  sentence_from(Lines, L, 12, Parts),
	    atomic_list_concat(Parts, ' ', T0), normalize_space(atom(T1), T0),
	    ascii_text(T1, T1a),
	    ( atom_length(T1a, Len), Len > 240 -> sub_atom(T1a, 0, 237, _, T2), atom_concat(T2, '...', Text) ; Text = T1a )
	;   Text = ''
	).

sentence_from(Lines, L, Max, Parts) :-
	(   Max > 0, nth1(L, Lines, S0)
	->  strip_comment(S0, S),
	    (   sub_string(S, _, 1, 0, ".")
	    ->  Parts = [S]
	    ;   L1 is L + 1, M1 is Max - 1, sentence_from(Lines, L1, M1, More), Parts = [S|More]
	    )
	;   Parts = []
	).

strip_comment(S0, S) :-
	( sub_string(S0, B, _, _, "%") -> sub_string(S0, 0, B, _, S1) ; S1 = S0 ),
	split_string(S1, "", " \t", [S]).

		 /*******************************
		 *	      the laws		*
		 *******************************/

/*  law_top/4: each law's conditions on the state before the call, as a local
    boolean, plus the snapshots its writes need. t(Id, Lines, LawInfo). */
law_top(ArgExprs, l(Kind, Id, T, Src), [t(Id, Lines, info(Kind, Guard, Ctx, Late, Src, T))|R], R) :-
	ctx_new(Id, Ctx0),
	T =.. [_, Ev|_],
	bind_event(Ev, ArgExprs, Ctx0, Ctx1, EvConds),
	law_parts(T, Pre, Late),
	(   guard_goal(Src,
		       ( cond_exprs(Pre, Ctx1, Ctx2, Es),
			 append(EvConds, Es, All),
			 snapshots(Id, T, Late, Ctx1, Ctx2, Ctx3, SnapLines),
			 (   All == []
			 ->  Guard0 = true, CondLines = []
			 ;   conj(All, C),
			     next_guard(Id, C, Guard0, L1),
			     src_comment(Src, Cm),
			     append(Cm, [L1], CondLines)
			 ),
			 append(CondLines, SnapLines, Lines0),
			 Out = r(Lines0, Guard0, Ctx3) ),
		       Out),
	    Out = r(Lines, Guard, Ctx)
	->  true
	;   Lines = [], Guard = true, Ctx = Ctx1
	).

%	A law's condition, as a local: one boolean each, or — in a function with
%	many laws, where so many locals would not fit the EVM's stack — one
%	memory array of them.
next_guard(Id, C, G, Line) :-
	(   b_getval(lps_sol_law_array, true)
	->  b_getval(lps_sol_law_count, I), I1 is I + 1, b_setval(lps_sol_law_count, I1),
	    format(atom(G), 'law[~d]', [I]),
	    format(atom(Line), '~w = ~w;', [G, C])
	;   format(atom(G), 'law~d', [Id]),
	    format(atom(Line), 'bool ~w = ~w;', [G, C])
	).

%	An update's conditions split: those that read the value being updated
%	(or anything computed from it) are evaluated when the update is written,
%	on the value the earlier writes left; the rest on the state before.
law_parts(updated(_, _, Old-_, Cond), Pre, Late) :- !,
	dependents(Cond, [Old], Dep),
	partition(late_literal(Dep), Cond, Late, Pre).
law_parts(T, Cond, []) :- T =.. L, last(L, Cond).

late_literal(Dep, C) :-
	C \= holds(_, _), sub_term(V, C), V = '$VAR'(_), memberchk_eq(V, Dep), !.

dependents(Cond, D0, D) :-
	(   member(C, Cond), ( C = (X is E) ; C = (X = E) ; C = (E = X) ),
	    X = '$VAR'(_), \+ memberchk_eq(X, D0),
	    sub_term(V, E), V = '$VAR'(_), memberchk_eq(V, D0)
	->  dependents(Cond, [X|D0], D)
	;   D = D0
	).

memberchk_eq(X, L) :- member(Y, L), Y == X, !.

%	Pre-state values that the writes use, copied into locals before any write.
snapshots(Id, T, Late, Ctx1, Ctx2, Ctx, Lines) :-
	law_write_terms(T, WTs),
	append(WTs, Late, Uses),
	term_variables_nv(Uses, Vs),
	findall(K-E, ( member('$VAR'(K), Vs), ctx_get(Ctx2, K, E), \+ ctx_get(Ctx1, K, _),
		       ctx_read(Ctx2, K) ), Snaps),
	foldl(snap(Id), Snaps, Ctx2-[], Ctx-Lines0),
	reverse(Lines0, Lines).

snap(Id, K-E, Ctx0-L0, Ctx-[Line|L0]) :-
	ctx_id(Ctx0, CId), var_node(CId, '$VAR'(K), N), node_type(N, T0), sol_type(T0, T),
	format(atom(V), 'v~d_~d', [Id, K]),
	( T == string -> Loc = ' memory' ; Loc = '' ),
	format(atom(Line), '~w~w ~w = ~w;', [T, Loc, V, E]),
	ctx_bind(Ctx0, K, V, Ctx).

law_write_terms(initiated(_, Fl, _), [Fl]).
law_write_terms(terminated(_, Fl, Cond), Ts) :-
	(   clearing_termination(Fl, Cond, Keys) -> Ts = Keys ; Ts = [Fl] ).
law_write_terms(updated(_, Fl, _-New, _), [Fl, New]).

term_variables_nv(T, Vs) :-
	findall(V, ( sub_term(V, T), V = '$VAR'(_) ), Vs0), sort(Vs0, Vs).

%	The writes, in LPS2's order: terminations, initiations, updates.
law_writes(Ls, Tops, ArgExprs, Lines) :-
	findall(Line, ( member(Kind, [terminated, initiated, updated]),
			member(l(Kind, Id, T, Src), Ls),
			member(t(Id, _, info(Kind, Guard, Ctx, Late, Src, T)), Tops),
			write_lines(Kind, T, Guard, Ctx, Late, Src, ArgExprs, WLs),
			member(Line, WLs) ), Lines).

write_lines(Kind, T, Guard, Ctx, Late, Src, _ArgExprs, Lines) :-
	guard_goal(Src, write_lines_(Kind, T, Guard, Ctx, Late, Lines0), Lines0),
	(   Guard == true, Lines0 \== []
	->  src_comment(Src, Cm), append(Cm, Lines0, Lines)
	;   Lines = Lines0
	).

write_lines_(terminated, terminated(_, Fl, Cond), Guard, Ctx, _, Lines) :-
	functor(Fl, F, N), s_fluent(F/N, Shape, VP),
	fluent_store(Ctx, Fl, Shape, VP, Value, Presence),
	(   Shape == functional
	->  Fl =.. [_|Args], nth1(VP, Args, V),
	    (   ( clearing_termination(Fl, Cond, _) ; V = '$VAR'(_), \+ bound(Ctx, V) )
	    ->  Test = Presence
	    ;   node_type(slot(fl(F/N), VP), VT), sx(Ctx, V, VT, EV),
		(   Presence == true -> format(atom(Test), '~w == ~w', [Value, EV])
		;   format(atom(Test), '~w && ~w == ~w', [Presence, Value, EV])
		)
	    ),
	    (   Presence == true
	    ->  format(atom(Do), 'delete ~w;', [Value])      % back to the default
	    ;   format(atom(Do), 'delete ~w; ~w = false;', [Value, Presence])
	    )
	;   Test = Presence,
	    format(atom(Do), '~w = false;', [Presence])
	),
	guarded(Guard, Test, Do, Lines).
write_lines_(initiated, initiated(_, Fl, _), Guard, Ctx, _, Lines) :-
	functor(Fl, F, N), s_fluent(F/N, Shape, VP),
	fluent_store(Ctx, Fl, Shape, VP, Value, Presence),
	(   Shape == functional
	->  Fl =.. [_|Args], nth1(VP, Args, V),
	    node_type(slot(fl(F/N), VP), VT0), sol_type(VT0, VT), sx(Ctx, V, VT, EV),
	    (   Presence == true -> format(atom(Do), '~w = ~w;', [Value, EV])
	    ;   format(atom(Do), '~w = ~w; ~w = true;', [Value, EV, Presence])
	    )
	;   format(atom(Do), '~w = true;', [Presence])
	),
	guarded(Guard, true, Do, Lines).
write_lines_(updated, updated(_, Fl, Old-New, _), Guard, Ctx0, Late, Lines) :-
	functor(Fl, F, N), s_fluent(F/N, functional, VP),
	fluent_store(Ctx0, Fl, functional, VP, Value, Presence),
	Old = '$VAR'(KO),
	ctx_bind(Ctx0, KO, Value, Ctx1),
	cond_exprs(Late, Ctx1, Ctx2, LateEs),
	node_type(slot(fl(F/N), VP), VT0), sol_type(VT0, VT),
	sx(Ctx2, New, VT, EN),
	( Presence == true -> conj(LateEs, Test) ; conj([Presence|LateEs], Test) ),
	format(atom(Do), '~w = ~w;', [Value, EN]),
	guarded(Guard, Test, Do, Lines).

%	A termination of a functional fluent that clears its key whatever the
%	value: the value is a variable its own conditions read from that very
%	fact (`… terminates owner(E) if owner(E)`), or nothing else mentions it.
%	Keys: the key arguments, which the write still needs.
clearing_termination(Fl, Cond, Keys) :-
	functor(Fl, F, N), s_fluent(F/N, functional, VP),
	key_value(Fl, VP, Keys, V), V = '$VAR'(_),
	(   member(holds(G, _), Cond), G == Fl
	->  true
	;   \+ ( member(C, Cond), sub_term(S, C), S == V )
	).

guarded(Guard, Test, Do, [L]) :-
	(   Guard == true, Test == true -> L = Do
	;   Guard == true -> format(atom(L), 'if (~w) { ~w }', [Test, Do])
	;   Test == true -> format(atom(L), 'if (~w) { ~w }', [Guard, Do])
	;   format(atom(L), 'if (~w && ~w) { ~w }', [Guard, Test, Do])
	).

		 /*******************************
		 *   invariants and constructor	*
		 *******************************/

invariant_code(Lines) :-
	b_setval(lps_sol_in_function, true),
	findall(L, ( s_clause(Id, d_pre, d_pre(Cond), Src, _), \+ member(happens(_, _, _), Cond),
		     ctx_new(Id, Ctx0),
		     guard_goal(Src,
				( cond_exprs(Cond, Ctx0, _, Es), conj(Es, C),
				  error_name(invariant/0, Src, EN),
				  src_comment(Src, Cm),
				  revert_stmt(EN, RS),
				  format(atom(L1), 'if (~w) ~w', [C, RS]),
				  append(Cm, [L1], Ls) ),
				Ls),
		     member(L, Ls) ), Lines),
	b_setval(lps_sol_in_function, false).

constructor_code(ctor(Params, Lines)) :-
	b_setval(lps_sol_in_function, false),
	b_setval(lps_sol_in_ctor, true),
	findall(Fl-Src, ( s_clause(_, initial, L, Src, _), member(Fl, L) ), Fs),
	findall(Ls, ( member(Fl-Src, Fs), init_lines(Fl, Src, Ls) ), Lss),
	b_setval(lps_sol_in_ctor, false),
	append(Lss, Lines0),
	%  every named account is a constructor parameter: an address is not
	%  something a program can name, so the deployer says who alice is; the
	%  ones the functions read are kept, as immutables
	findall(Nm-A, s_account(A, Nm), NAs0), sort(NAs0, NAs),
	findall(address-PN, ( member(Nm-_, NAs), atom_concat(Nm, '_', PN) ), Params),
	findall(L, ( member(Nm-A, NAs), s_account_used(A), atom_concat(Nm, '_', PN),
		     format(atom(L), '~w = ~w;', [Nm, PN]) ), AccLines),
	append(AccLines, Lines0, Lines).

init_lines(Fl, Src, Lines) :-
	functor(Fl, F, N),
	(   s_fluent(F/N, Shape, VP)
	->  ctx_new(0, Ctx),
	    guard_goal(Src,
		       ( fluent_store(Ctx, Fl, Shape, VP, Value, Presence),
			 (   Shape == functional
			 ->  Fl =.. [_|Args], nth1(VP, Args, V),
			     node_type(slot(fl(F/N), VP), VT0), sol_type(VT0, VT), sx(Ctx, V, VT, EV),
			     (   Presence == true -> format(atom(L), '~w = ~w;', [Value, EV])
			     ;   format(atom(L), '~w = ~w; ~w = true;', [Value, EV, Presence])
			     )
			 ;   format(atom(L), '~w = true;', [Presence])
			 ),
			 Lines = [L] ),
		       Lines)
	;   Lines = []
	).

		 /*******************************
		 *	     writing it out	*
		 *******************************/

write_contract(P, Options, Contract, Fns, Inv, ctor(CParams, CLines), TLs) :-
	option(origin(Origin), Options, 'an LPS program'),
	file_base_name(Origin, OB),
	format('// SPDX-License-Identifier: UNLICENSED~n'),
	format('pragma solidity ^0.8.20;~n~n'),
	format('/// @title ~w~n', [Contract]),
	format('/// @notice Generated from ~w by LPS2 (Misc > Deploy as Solidity): fluents are state,~n', [OB]),
	format('///         actions are functions (the first argument, when it is someone, is msg.sender),~n'),
	format('///         integrity constraints are reverts, causal laws are the state writes.~n'),
	format('/// @dev    A fluent that can be absent has a has* flag beside it: LPS tells "no value"~n'),
	format('///         from 0, and so does the contract.~n'),
	write_scenario_comment(P),
	format('contract ~w {~n', [Contract]),
	%  state
	(   s_constant(_, _, _)
	->  format('~n    // ---- named constants ----~n'),
	    forall(s_constant(_, V, CN), format('    uint256 public constant ~w = ~w;~n', [CN, V]))
	;   true
	),
	format('~n    // ---- the fluents ----~n'),
	forall(s_fluent(FN, Shape, VP), write_fluent_decl(FN, Shape, VP)),
	findall(A-N, ( s_account_used(A), s_account(A, N) ), UAs0), sort(UAs0, UAs),
	(   UAs \== []
	->  format('~n    // ---- named accounts the rules mention (set at deployment) ----~n'),
	    forall(member(_-N, UAs), format('    address public immutable ~w;~n', [N]))
	;   true
	),
	(   s_symbol(_, _)
	->  format('~n    // ---- names ----~n'),
	    forall(s_symbol(S, SN), ( atom_length(S, SL),
				       ( SL =< 32 -> format('    bytes32 public constant ~w = "~w";~n', [SN, S])
				       ; format('    bytes32 public constant ~w = keccak256("~w");~n', [SN, S]) ) ))
	;   true
	),
	%  errors
	(   s_error(_, _, _)
	->  format('~n    // ---- the integrity constraints, as errors ----~n'),
	    forall(s_error(EN, L, Text-_),
		   (   Text == '' -> format('    error ~w();~n', [EN])
		   ;   format('    /// line ~d: ~w~n    error ~w();~n', [L, Text, EN])
		   ))
	;   true
	),
	%  events
	format('~n    // ---- the actions, as they happen ----~n'),
	forall(member(fn(AN, fn(_, _, _, EvArgs, _)), Fns),
	       ( event_name(AN, EvN), ev_params(AN, EvArgs, EPs),
		 format('    event ~w(~w);~n', [EvN, EPs]) )),
	%  constructor
	format('~n    constructor('),
	findall(S, ( member(T-X, CParams), format(atom(S), '~w ~w', [T, X]) ), CPs),
	atomic_list_concat(CPs, ', ', CPT),
	format('~w) {~n', [CPT]),
	forall(member(L, CLines), format('        ~w~n', [L])),
	format('    }~n'),
	%  functions
	forall(member(fn(_, Fn), Fns), write_function(Fn)),
	%  invariants and helpers
	(   Inv \== []
	->  format('~n    /// The constraints that name no action: checked after every call.~n'),
	    format('    function _checkInvariants() internal view {~n'),
	    forall(member(L, Inv), format('        ~w~n', [L])),
	    format('    }~n')
	;   true
	),
	forall(s_helper(H), write_helper(H)),
	forall(member(TL, TLs), write(TL)),
	format('}~n').

ev_params(AN, EvArgs, Text) :-
	AN = A/N,
	findall(S, ( member(I-(T-_), EvArgs),
		     ( I =:= 1, s_caller(A/N) -> caller_word(A/N, W) ; s_name(param(A/N, I), W) -> true ; format(atom(W), 'arg~d', [I]) ),
		     sol_type(T, T1),
		     ( T1 == address -> Ix = ' indexed' ; Ix = '' ),
		     format(atom(S), '~w~w ~w', [T1, Ix, W]) ), Ss),
	indexed_limit(Ss, Ss1),
	atomic_list_concat(Ss1, ', ', Text).

caller_word(AN, W) :-
	slot_names(AN, [W0|_]), W0 \== '', camel(W0, W1), \+ reserved(W1), !, W = W1.
caller_word(_, caller).

%	at most three indexed parameters per event
indexed_limit(Ss, Out) :- indexed_limit(Ss, 0, Out).
indexed_limit([], _, []).
indexed_limit([S|Ss], K, [S1|Out]) :-
	(   sub_atom(S, B, _, _, ' indexed ')
	->  (   K < 3 -> S1 = S, K1 is K + 1
	    ;   sub_atom(S, 0, B, _, Pre), sub_atom(S, _, _, 0, After0), atom_concat(' indexed ', Rest, After0), !,
		atomic_list_concat([Pre, ' ', Rest], S1), K1 = K
	    )
	;   S1 = S, K1 = K
	),
	indexed_limit(Ss, K1, Out).

write_fluent_decl(F/N, Shape, VP) :-
	fluent_name(F/N, Name),
	fluent_template(F/N, Cm),
	format('    /// ~w~n', [Cm]),
	(   Shape == bool
	->  format('    bool public ~w;~n', [Name])
	;   Shape == set
	->  positions(N, Ps),
	    mapping_type(F/N, Ps, bool, MT),
	    format('    ~w public ~w;~n', [MT, Name])
	;   positions_except(N, VP, KPs),
	    node_type(slot(fl(F/N), VP), VT0), sol_type(VT0, VT),
	    mapping_type(F/N, KPs, VT, MT),
	    format('    ~w public ~w;~n', [MT, Name]),
	    (   s_default(F/N, _)
	    ->  true                        % Solidity's zero is the declared default
	    ;   mapping_type(F/N, KPs, bool, HT),
		presence_name(F/N, HN),
		format('    ~w public ~w;~n', [HT, HN])
	    )
	).

positions(N, Ps) :- numlist_(1, N, Ps).

mapping_type(_, [], VT, VT) :- !.
mapping_type(FN, [P|Ps], VT, MT) :-
	node_type(slot(fl(FN), P), KT0), sol_type(KT0, KT),
	mapping_type(FN, Ps, VT, Inner),
	format(atom(MT), 'mapping(~w => ~w)', [KT, Inner]).

write_function(fn(Name, Params, Body, _, Comment)) :-
	format('~n    /// ~w~n', [Comment]),
	findall(S, ( member(T-X, Params), ( T == string -> format(atom(S), 'string calldata ~w', [X]) ; format(atom(S), '~w ~w', [T, X]) ) ), Ps),
	atomic_list_concat(Ps, ', ', PT),
	format('    function ~w(~w) external {~n', [Name, PT]),
	forall(member(L, Body), format('        ~w~n', [L])),
	format('    }~n').

write_helper(min) :-
	format('~n    function _min(uint256 a, uint256 b) internal pure returns (uint256) { return a < b ? a : b; }~n').
write_helper(max) :-
	format('~n    function _max(uint256 a, uint256 b) internal pure returns (uint256) { return a > b ? a : b; }~n').

%	a ground timeless fact table, as a pure lookup
write_timeless(F/N, HN) :-
	findall(Args, ( s_clause(_, timeless, l_timeless(H, B), _, _), ( B == true ; B == [] ),
			functor(H, F, N), H =.. [_|Args] ), Rows),
	findall(S, ( between(1, N, I), node_type(slot(tl(F/N), I), T0), sol_type(T0, T),
		     ( T == string -> format(atom(S), 'string memory a~d', [I]) ; format(atom(S), '~w a~d', [T, I]) ) ), Ps),
	atomic_list_concat(Ps, ', ', PT),
	%  a table naming an account reads an immutable: view, not pure
	(   member(Args, Rows), nth1(I, Args, A), atom(A), \+ zero_address(A),
	    node_type(slot(tl(F/N), I), address)
	->  Mut = view
	;   Mut = pure
	),
	format('~n    /// the timeless facts ~w/~w~n', [F, N]),
	format('    function ~w(~w) internal ~w returns (bool) {~n', [HN, PT, Mut]),
	ctx_new(0, Ctx),
	forall(member(Args, Rows),
	       ( findall(C, ( nth1(I, Args, A), node_type(slot(tl(F/N), I), T0), sol_type(T0, T),
			      sx(Ctx, A, T, E),
			      ( T == string -> format(atom(C), 'keccak256(bytes(a~d)) == keccak256(bytes(~w))', [I, E])
			      ; format(atom(C), 'a~d == ~w', [I, E]) ) ), Cs),
		 conj(Cs, Cj),
		 format('        if (~w) return true;~n', [Cj]) )),
	format('        return false;~n    }~n').

%	The program's observations, as the calls that replay them.
write_scenario_comment(_P) :-
	findall(T-E, ( s_clause(_, observe, observe(Es, T), _, _), member(E, Es) ), TEs0),
	msort(TEs0, TEs),
	(   TEs == [] -> true
	;   format('///~n/// @custom:scenario The program''s own scenario, as calls (deploy, then call in this order):~n'),
	    forall(nth1(K, TEs, T-E), scenario_line(K, T, E))
	),
	format('///~n').

scenario_line(K, T, E) :-
	(   callable(E), functor(E, A, N), s_action(A/N), action_name(A/N, Name)
	->  E =.. [_|Args],
	    (   s_caller(A/N), Args = [C|Rest] -> format(atom(Who), '~w: ', [C]), First = 2
	    ;   Rest = Args, Who = '', First = 1
	    ),
	    %  in the function's parameter order (abi_order/2)
	    findall(T1-X, ( nth0(J, Rest, X), I is First + J,
			    ( node_type(slot(ac(A/N), I), T0) -> sol_type(T0, T1) ; T1 = unknown ) ), TXs),
	    abi_order(TXs, Ordered),
	    findall(S, ( member(_-X, Ordered), format(atom(S), '~W', [X, [quoted(true)]]) ), Ss),
	    atomic_list_concat(Ss, ', ', AT),
	    format('///   ~d. (time ~w) ~w~w(~w)~n', [K, T, Who, Name, AT])
	;   format('///   ~d. (time ~w) ~q~n', [K, T, E])
	).

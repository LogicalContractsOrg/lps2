/* lps_program.pl — the compiled, immutable program (§I.2.1).

   A *program* is everything that does not change while a session runs:
   reactive rules, intensional-fluent clauses, composite-event clauses,
   timeless clauses, causal laws, preconditions, declarations, and the
   module holding the user's plain Prolog. Many sessions share one program;
   nothing here is ever mutated after `lps_compile_terms/5` returns.

   The internal vocabulary is the one §I.3 fixes — `reactive_rule/2`,
   `l_int/2`, `l_events/2`, `l_timeless/2`, `d_pre/1`, `initiated/3`,
   `terminated/3`, `updated/4`, `initial_state/1`, `observe/2` and the
   declaration predicates. It is deliberately *not* re-invented: `dump/0`
   output has to stay readable by the old engine, and the plan calls the
   vocabulary an interface specification.

   Two additions, both from §I.3:

     1. every clause carries provenance, in a side table keyed by clause id,
	so `dump/0` output is unchanged but the LSP and the explanation
	forest can find the source;
     2. clause families are indexed by functor/arity. Indexing must preserve
	*source order* within a family, because source order is selection
	order (selection_spec SP3) and therefore part of the conformance
	contract.

   Clauses are copied on retrieval. Upstream keeps them in dynamic predicates,
   so every call gets a fresh instance; sharing them here instead would let one
   resolution step bind another's variables.
*/

:- module(lps_program, [
	lps_compile_terms/5,     % +Terms, +Options, -Program, -Diags, +Origin

	prog_id/2, prog_module/2, prog_rules/2, prog_rules_pri/2,
	prog_initiated/2, prog_terminated/2, prog_updated/2,
	prog_d_pre/2, prog_d_pre_class/2, prog_initial/2, prog_observe/2,
	prog_settings/2, prog_setting/3, prog_provenance/2,
	prog_l_int_all/2, prog_l_events_all/2, prog_l_timeless_all/2,
	prog_externals/2,

	p_l_int/3,               % +Prog, ?Head, ?Body       (nondet, source order)
	p_l_events/3,            % +Prog, ?Head, ?Body
	p_l_timeless/3,          % +Prog, ?Head, ?Body
	p_initiated/4,           % +Prog, ?Ev, ?Fluent, ?Cond
	p_initiated/5,           % +Prog, ?Index, ?Ev, ?Fluent, ?Cond
	p_terminated/4,
	p_terminated/5,
	p_updated/5,             % +Prog, ?Ev, ?Fluent, ?Change, ?Cond
	p_updated/6,
	p_d_pre/2,               % +Prog, ?Conds
	p_d_pre/3,               % +Prog, ?Type, ?Conds
	p_observe/3,             % +Prog, ?Events, ?Time
	p_initial_state/2,
	p_reactive_rules/2,      % +Prog, -List of reactive_rule(A,C)

	% derived declaration predicates (interpreter.P's "internal predicates
	% necessary to aggregate all declarations")
	p_action/2,              % +Prog, ?Action        — action_/1
	p_event/2,               % +Prog, ?Event         — event_/1
	p_fluent/2,              % +Prog, ?Fluent        — fluent_/1
	p_user_fluent_decl/2,
	p_intensional/2,         % +Prog, +Pred
	p_macroaction/2,         % +Prog, +Event
	p_system_action/2,
	p_editing_action/2,
	p_external/2,            % +Prog, ?Pred
	p_unserializable/2,
	p_prolog_events/2,
	p_user_fluent/2,
	p_d_head/2,
	p_d_event/2,
	p_call/2,                % +Prog, +Goal          — call user Prolog
	p_clause_src/5,          % +Prog, ?Family, ?Index, ?Term, ?Src
	p_term_src/3,            % +Prog, +Term, -Src
	prov_family/2,           % ?Name, ?FamilyNumber
	p_has_ite/1,
	p_program_predicate/1,
	p_fluent_default/4,      % +Prog, +Fluent, -Key, -Default
	p_defaults/2             % +Prog, -DefaultTerms
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(assoc)).
:- use_module(library(yall)).
:- use_module(lps_ops).
:- use_module(lps_diag).
:- use_module(lps_builtins).

:- dynamic prog_counter/1.
prog_counter(0).

/* The program term. Field order is fixed; use the accessors. */
%   1 Id  2 Module  3 Rules  4 RulesPri  5 LIntIdx  6 LIntAll  7 LEvIdx
%   8 LEvAll  9 LTlIdx  10 LTlAll  11 Initiated  12 Terminated  13 Updated
%  14 DPre  15 DPreClass  16 Initial  17 Observe  18 Decls  19 Externals
%  20 Settings  21 Prov

prog_id(P, X)          :- arg(1, P, X).
prog_module(P, X)      :- arg(2, P, X).
prog_rules(P, X)       :- arg(3, P, X).
prog_rules_pri(P, X)   :- arg(4, P, X).
prog_l_int_all(P, X)   :- arg(6, P, X).
prog_l_events_all(P, X):- arg(8, P, X).
prog_l_timeless_all(P, X) :- arg(10, P, X).
prog_initiated(P, X)   :- arg(11, P, X).
prog_terminated(P, X)  :- arg(12, P, X).
prog_updated(P, X)     :- arg(13, P, X).
prog_d_pre(P, X)       :- arg(14, P, X).
prog_d_pre_class(P, X) :- arg(15, P, X).
prog_initial(P, X)     :- arg(16, P, X).
prog_observe(P, X)     :- arg(17, P, X).
prog_decls(P, X)       :- arg(18, P, X).
prog_externals(P, X)   :- arg(19, P, X).
prog_settings(P, X)    :- arg(20, P, X).
prog_provenance(P, X)  :- arg(21, P, X).

%!	prog_setting(+Program, +Key, -Value) is semidet.
%
%	A program setting may be a *rule*, not just a fact —
%	`simulatedRealTimePerCycle(RTPC) :- RTPC is 3600*12.` occurs in the
%	corpus. Upstream reaches every one of these by calling into the program
%	module, so a fact and a rule are interchangeable; capturing only facts
%	at compile time silently gives such a program no simulated clock at all.
prog_setting(P, Key, Value) :-
	prog_settings(P, S),
	(   memberchk(Key-V, S)
	->  Value = V
	;   computed_setting(Key),
	    prog_module(P, M),
	    G =.. [Key, Value],
	    catch(once(call(M:G)), _, fail)
	).

computed_setting(maxTime).
computed_setting(maxRealTime).
computed_setting(minCycleTime).
computed_setting(simulatedRealTimePerCycle).
computed_setting(simulatedRealTimeBeginning).

		 /*******************************
		 *	    compilation		*
		 *******************************/

%!	lps_compile_terms(+Terms, +Options, -Program, -Diags, +Origin) is det.
%
%	Terms are raw terms, `t(Term, Line)` pairs, or `t(Term, src(File,
%	Line, Col, Kind))` pairs. Origin names the file (or buffer) for
%	provenance; a term that carries a full `src/4` keeps it instead, which
%	is how an LE-sourced program (§I.9, M8a) points its diagnostics back
%	into the `.le` document rather than into generated internal text.
lps_compile_terms(Terms0, Options, Program, Diags, Origin) :-
	maplist(normalise_term, Terms0, Terms),
	new_program_module(Id, Module),
	partition_terms(Terms, Origin, Acc0),
	%  Directives first: a `use_module` may bring in the operators or the
	%  predicates the program's own clauses call.
	apply_directives(Module, Origin, Terms, DirDiags),
	assert_all_clauses(Module, Terms),
	build_program(Id, Module, Acc0, Options, Origin, Program),
	check_program(Program, CheckDiags),
	append(DirDiags, CheckDiags, Diags).

normalise_term(t(T, L), t(T, L)) :- !.
normalise_term(T, t(T, 0)).

new_program_module(Id, Module) :-
	retract(prog_counter(N)),
	N1 is N + 1,
	assertz(prog_counter(N1)),
	format(atom(Id), 'lps_prog_~w', [N1]),
	Module = Id,
	%  Bring the module into existence even when the program has no Prolog
	%  clauses of its own. A module with no predicates does not exist as far
	%  as current_predicate/1 is concerned, and p_external/2 asks exactly
	%  that question — without this, `holds(true,T)` stops resolving.
	dynamic(Module:'$lps_program_module'/0),
	assertz(Module:'$lps_program_module'),
	%  The engine's own predicates are visible from the program's module, as
	%  they are from upstream's `db`: a program's Prolog may legitimately ask
	%  the engine what time it is or what the state contains, and one corpus
	%  program wires exactly that in as a polled event:
	%     new_lustrum(N) :- current_time(T), 0 is T mod 5, N is T/5.
	%  Importing rather than fallback-calling matters because the call
	%  happens inside the *program's* clause body, not at the top level.
	add_import_module(Module, lps_builtins, end),
	predeclare_vocabulary(Module).

/* Every predicate of the internal vocabulary exists in every program module,
   with no clauses if the program has none.

   The engine probes the module for these — `prog_setting/3` calls
   maxRealTime/1 and friends because a setting may be a rule, p_observe/3 calls
   observe/2, the planner calls achieve/1 — and a probe for a predicate that
   does not exist is not a cheap failure in SWI: it runs the autoloader, which
   searches the library index before giving up, on *every* call. Measured on
   forTesting/prospectiveGoat2, that was 6,468 library-index searches in ten
   cycles, around 7% of the run, for predicates that were never going to be
   found.

   Declaring them dynamic makes the probe an ordinary failure. It cannot change
   what counts as an external predicate (§I.4, SP16): p_external/2 excludes
   everything p_program_predicate/1 names, which is exactly this list.
*/
predeclare_vocabulary(Module) :-
	forall(( program_predicate_(T), functor(T, Name, Arity) ),
	       make_dynamic(Module, Name, Arity)).

/* acc(...) accumulates during the single pass over the source terms. Each
   family keeps source order.
*/
partition_terms(Terms, Origin, Acc) :-
	empty_acc(Acc0),
	foldl(partition_term(Origin), Terms, Acc0, Acc1),
	finish_acc(Acc1, Acc).

empty_acc(acc([],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[],[])).

%  acc fields: 1 rules 2 rulespri 3 l_int 4 l_events 5 l_timeless 6 initiated
%  7 terminated 8 updated 9 d_pre 10 initial 11 observe 12 fluent1 13 fluents
%  14 action1 15 actions 16 event1 17 events 18 prolog_events
%  19 unserializable 20 settings 21 user clauses + provenance

acc_add(N, X, A0, A) :-
	arg(N, A0, L),
	setarg_copy(N, A0, [X|L], A).

%	Functional update of one argument (the accumulator is small; copying
%	keeps the compiler free of destructive assignment).
setarg_copy(N, T0, V, T) :-
	T0 =.. [F|Args0],
	nth1(N, Args0, _, Rest),
	nth1(N, Args, V, Rest),
	T =.. [F|Args].

partition_term(Origin, t(Term, Loc), A0, A) :-
	(   Loc = src(_, _, _, _)      % a full position, e.g. from LE2 (§I.9)
	->  Src = Loc
	;   Src = src(Origin, Loc, 0, internal)
	),
	partition_term_(Term, Src, A0, A).

partition_term_(reactive_rule(Ant, Cons), S, A0, A) :- !,
	acc_add(1, p(reactive_rule(Ant, Cons), S), A0, A).
partition_term_(reactive_rule(Ant, Cons, Pri), S, A0, A) :- !,
	acc_add(2, p(reactive_rule(Ant, Cons, Pri), S), A0, A).
partition_term_(l_int(H, B), S, A0, A) :- !,
	acc_add(3, p(l_int(H, B), S), A0, A).
partition_term_(l_events(H, B), S, A0, A) :- !,
	acc_add(4, p(l_events(H, B), S), A0, A).
partition_term_(l_timeless(H, B), S, A0, A) :- !,
	acc_add(5, p(l_timeless(H, B), S), A0, A).
partition_term_(initiated(E, F, C), S, A0, A) :- !,
	acc_add(6, p(initiated(E, F, C), S), A0, A).
partition_term_(terminated(E, F, C), S, A0, A) :- !,
	acc_add(7, p(terminated(E, F, C), S), A0, A).
partition_term_(updated(E, F, Ch, C), S, A0, A) :- !,
	acc_add(8, p(updated(E, F, Ch, C), S), A0, A).
partition_term_(d_pre(C), S, A0, A) :- !,
	acc_add(9, p(d_pre(C), S), A0, A).
partition_term_(initial_state(L), S, A0, A) :- !,
	acc_add(10, p(L, S), A0, A).
partition_term_(observe(E, T), S, A0, A) :- !,
	acc_add(11, p(observe(E, T), S), A0, A).
partition_term_(fluent(F), S, A0, A) :- !,
	acc_add(12, p(F, S), A0, A).
partition_term_(fluents(L), S, A0, A) :- !,
	acc_add(13, p(L, S), A0, A).
partition_term_(action(X), S, A0, A) :- !,
	acc_add(14, p(X, S), A0, A).
partition_term_(actions(L), S, A0, A) :- !,
	acc_add(15, p(L, S), A0, A).
partition_term_(event(X), S, A0, A) :- !,
	acc_add(16, p(X, S), A0, A).
partition_term_(events(L), S, A0, A) :- !,
	acc_add(17, p(L, S), A0, A).
partition_term_(prolog_events(L), S, A0, A) :- !,
	acc_add(18, p(L, S), A0, A).
partition_term_(unserializable(L), S, A0, A) :- !,
	acc_add(19, p(L, S), A0, A).
%	`defaults([balance(_, 0), owner(zero)])` — an LPS2 declaration beside
%	fluents/1 (LE2's `; 0 by default`, docs/le_lps_surface.md §2): the value
%	a fluent's last argument has for a key no fact is stored for.
partition_term_(defaults(L), S, A0, A) :- !,
	acc_add(20, p(defaults-L, S), A0, A).
partition_term_(Setting, S, A0, A) :-
	setting_term(Setting, Key, Value), !,
	acc_add(20, p(Key-Value, S), A0, A).
%	`:- lps_engine(planning, [...])` is a *directive*, because it changes how
%	the whole program is run rather than stating anything about the domain.
%	Under the default lps_engine(reactive) an `achieve` is a compile error,
%	so no legacy program can acquire planner semantics by accident (§I.7.2).
partition_term_((:- lps_engine(Mode, Opts)), S, A0, A) :- !,
	acc_add(20, p(engine-Mode, S), A0, A1),
	acc_add(20, p(engine_options-Opts, S), A1, A).
partition_term_((:- lps_engine(Mode)), S, A0, A) :- !,
	acc_add(20, p(engine-Mode, S), A0, A1),
	acc_add(20, p(engine_options-[], S), A1, A).
partition_term_((:- _), _, A, A) :- !.
partition_term_(display(_, _), _, A, A) :- !.
partition_term_(display3d(_, _), _, A, A) :- !.
partition_term_(Clause, S, A0, A) :-
	acc_add(21, p(Clause, S), A0, A).

setting_term(maxTime(X), maxTime, X).
setting_term(maxRealTime(X), maxRealTime, X).
setting_term(minCycleTime(X), minCycleTime, X).
setting_term(simulatedRealTimePerCycle(X), simulatedRealTimePerCycle, X).
setting_term(simulatedRealTimeBeginning(X), simulatedRealTimeBeginning, X).

%	Each family was accumulated in reverse; put it back in source order.
finish_acc(A0, A) :-
	A0 =.. [F|Args0],
	maplist(reverse, Args0, Args),
	A =.. [F|Args].

acc_field(N, A, L) :- arg(N, A, L0), maplist([p(X,_),X]>>true, L0, L).
acc_field_src(N, A, L) :- arg(N, A, L).

		 /*******************************
		 *	 user Prolog clauses	*
		 *******************************/

%	Everything the source file contains that is not internal LPS syntax is
%	the user's own Prolog: timeless predicates, helper code, the
%	external extensional fluents and external basic actions of §I.4. It
%	goes into the program's own module, where `p_call/2` reaches it.
/* *Every* source term goes into the module, not just the ones that are not
   internal LPS syntax. Upstream loads the whole `_.P` into `db`, so a program
   can call its own declarations as ordinary predicates — and one does:

	valid_contract at T if maxTime(Max), between(1,Max,T).

   Reading `maxTime/1` out into a settings list and nowhere else leaves that
   goal undefined. The program structure and the module are two views of the
   same clauses, and p_program_predicate/1 keeps the internal vocabulary out
   of the *external* predicate set (p_external/2) regardless.
*/
assert_all_clauses(Module, Terms) :-
	forall(( member(t(C, _), Terms), C \= (:- _) ),
	       assert_user_clause(Module, C)).

/* Directives (§17 of docs/lps_summary.md).

   A program is a Prolog file and may reasonably say

       :- use_module(library(clpfd)).
       :- dynamic seen/1.

   Both are honoured, by different routes. `dynamic/1` and its neighbours only
   touch the program's own module, so the core applies them itself. `use_module/1`
   reads a file, which is exactly what src/core/ may not do — so the core decides
   that the directive is admissible and hands the loading to src/edges/, by the
   same late-binding test read_source_terms/3 uses. A core-only deployment then
   has no loadable directives rather than a missing dependency.

   Anything else is ignored, silently and deliberately: the corpus carries
   directives meant for the old engine's SWISH host, and warning about each of
   them would be noise about a program that runs perfectly well.
*/
apply_directives(Module, Origin, Terms, Diags) :-
	findall(D,
		( member(t((:- G), _Src), Terms),
		  apply_directive(Module, Origin, G, Ds),
		  member(D, Ds) ),
		Diags).

apply_directive(_, _, G, []) :- var(G), !.
apply_directive(_, _, lps_engine(_), []) :- !.        % read by partition_terms/3
apply_directive(_, _, lps_engine(_, _), []) :- !.
apply_directive(Module, _, G, []) :-
	module_local_directive(G), !,
	catch(Module:G, _, true).
apply_directive(Module, Origin, G, Diags) :-
	loadable_directive(G), !,
	(   current_predicate(lps_source:lps_load_directive/4)
	->  lps_source:lps_load_directive(Module, Origin, G, Diags)
	;   Diags = []
	).
apply_directive(_, _, _, []).

module_local_directive(dynamic(_)).
module_local_directive(discontiguous(_)).
module_local_directive(multifile(_)).
module_local_directive(table(_)).
module_local_directive(op(_, _, _)).

loadable_directive(use_module(_)).
loadable_directive(use_module(_, _)).
loadable_directive(ensure_loaded(_)).

assert_user_clause(Module, Clause) :-
	(   Clause = (H :- _)
	->  true
	;   H = Clause
	),
	(   callable(H)
	->  functor(H, Name, Arity),
	    (	predicate_property(Module:H, dynamic)
	    ->	true
	    ;	make_dynamic(Module, Name, Arity)
	    ),
	    catch(assertz(Module:Clause), _, true)
	;   true
	).

%	A program may define a predicate whose name is already imported into
%	its module — `display/2` from library(edinburgh), `partition/4` from
%	library(apply), both of which occur in the corpus. The program's own
%	definition must win: these are its clauses, and the engine calls them
%	through p_call/2. Dropping the import first is the only way SWI allows
%	that.
make_dynamic(Module, Name, Arity) :-
	functor(Head, Name, Arity),
	%  redefine_system_predicate/1 first, and unconditionally: when the name
	%  is *imported* rather than local, dynamic/1 succeeds without complaint
	%  and calls still resolve to the import. `display/2` is the case that
	%  matters — it comes from library(edinburgh), ten corpus programs define
	%  their own, and without this their clauses are silently shadowed by a
	%  predicate that writes to a stream.
	catch(Module:redefine_system_predicate(Head), _, true),
	catch(dynamic(Module:Name/Arity), _,
	      ( catch(abolish(Module:Name/Arity), _, true),
		catch(dynamic(Module:Name/Arity), _, true) )).

		 /*******************************
		 *	    assembly		*
		 *******************************/

build_program(Id, Module, Acc, Options, Origin, Program) :-
	acc_field(1, Acc, Rules),
	acc_field(2, Acc, RulesPri),
	acc_field(3, Acc, LIntAll),
	acc_field(4, Acc, LEvAll),
	acc_field(5, Acc, LTlAll),
	acc_field(6, Acc, Initiated),
	acc_field(7, Acc, Terminated),
	acc_field(8, Acc, Updated),
	acc_field(9, Acc, DPreT),
	maplist([d_pre(C), C]>>true, DPreT, DPre),
	acc_field(10, Acc, InitialL),
	acc_field(11, Acc, Observe),
	acc_field(12, Acc, Fluent1),
	acc_field(13, Acc, FluentsL),
	acc_field(14, Acc, Action1),
	acc_field(15, Acc, ActionsL),
	acc_field(16, Acc, Event1),
	acc_field(17, Acc, EventsL),
	acc_field(18, Acc, PrologEventsL),
	acc_field(19, Acc, UnserL),
	acc_field(20, Acc, Settings0),
	acc_field_src(21, Acc, UserClauses),
	index_by_head([H, Key]>>(H = l_int(holds(F, _), _), key_of(F, Key)),
		      LIntAll, LIntIdx),
	index_by_head([H, Key]>>(H = l_events(happens(E, _, _), _), key_of(E, Key)),
		      LEvAll, LEvIdx),
	index_by_head([H, Key]>>(H = l_timeless(Hd, _), key_of(Hd, Key)),
		      LTlAll, LTlIdx),
	maplist(classify_precondition_pair, DPre, DPreClass),
	externals_of(UserClauses, Externals),
	Decls = decls(Fluent1, FluentsL, Action1, ActionsL, Event1, EventsL,
		      PrologEventsL, UnserL),
	has_ite_in(Rules, LIntAll, LEvAll, HasIte),
	default_index(Settings0, DefIdx),
	append(Settings0, [has_ite-HasIte, origin-Origin, options-Options,
			   default_index-DefIdx], Settings),
	collect_provenance(Acc, Prov),
	Program = lps_prog(Id, Module, Rules, RulesPri, LIntIdx, LIntAll,
			   LEvIdx, LEvAll, LTlIdx, LTlAll, Initiated, Terminated,
			   Updated, DPre, DPreClass, InitialL, Observe, Decls,
			   Externals, Settings, Prov).

%	F/N -> the declared default term, from every defaults/1 of the program.
default_index(Settings, Idx) :-
	findall(Key-D, ( member(defaults-L, Settings), member(D, L), compound(D),
			 functor(D, F, N), Key = F/N ), Pairs),
	list_to_assoc_first(Pairs, Idx).

list_to_assoc_first(Pairs, Assoc) :-
	empty_assoc(E),
	foldl([K-V, A0, A]>>( get_assoc(K, A0, _) -> A = A0 ; put_assoc(K, A0, V, A) ),
	      Pairs, E, Assoc).

%!	p_fluent_default(+Prog, +Fluent, -Key, -Default) is semidet.
%
%	Fluent is an instance of a fluent with a declared default: Key is the
%	fluent with its value (last argument) free, Default the declared value.
%	Fails at once for a fluent with no default — this is on the path of
%	every state lookup.
p_fluent_default(P, Fl, Key, Default) :-
	compound(Fl),
	arg(20, P, S), memberchk(default_index-Idx, S),
	\+ empty_assoc(Idx),
	compound_name_arity(Fl, F, N),
	get_assoc(F/N, Idx, D),
	arg(N, D, Default0), copy_term(Default0, Default),
	Fl =.. [F|As], append(Ks, [_], As),
	append(Ks, [_], KAs), Key =.. [F|KAs].

%!	p_defaults(+Prog, -Defaults) is det.
p_defaults(P, Ds) :-
	arg(20, P, S),
	(   memberchk(default_index-Idx, S) -> assoc_to_values(Idx, Ds) ; Ds = [] ).

key_of(T, Key) :-
	(   compound(T)
	->  compound_name_arity(T, N, A), Key = N/A
	;   atom(T)
	->  Key = T/0
	;   Key = '$var'
	).

index_by_head(KeyOf, Clauses, Idx) :-
	empty_assoc(E),
	foldl(index_one(KeyOf), Clauses, E, Idx0),
	map_assoc(reverse, Idx0, Idx).

index_one(KeyOf, Clause, A0, A) :-
	(   call(KeyOf, Clause, Key)
	->  true
	;   Key = '$var'
	),
	(   get_assoc(Key, A0, L)
	->  put_assoc(Key, A0, [Clause|L], A)
	;   put_assoc(Key, A0, [Clause], A)
	).

%	interpreter:classify_precondition/2 — does this denial talk about the
%	next state as well as the current one?
classify_precondition_pair(Cond, Type-Cond) :-
	classify_precondition(Cond, Type).

classify_precondition(Cond, Type) :-
	member(happens(_, _Current, Next), Cond), !,
	(   ( member(holds(_, T), Cond), T == Next )
	->  Type = both
	;   Type = current
	).
classify_precondition(_, both).

%	Program predicates are not external: upstream filters them out of
%	external_predicate_for_lps/1, and leaving `maxTime/1` in would make it an
%	external extensional fluent.
externals_of(UserClauses, Externals) :-
	findall(F/A,
		( member(p(C, _), UserClauses),
		  ( C = (H :- _) -> true ; H = C ),
		  callable(H),
		  \+ p_program_predicate(H),
		  functor(H, F, A) ),
		L0),
	list_to_set(L0, L1),
	append(L1, [uassert/1, uasserta/1, uassertz/1, uretract/1, uretractall/1],
	       Externals).

%	if-then-else spawns goal-child bookkeeping, which is the only consumer
%	of the (non-backtrackable, and therefore expensive) child relation.
%	Recording it for programs that cannot use it would be pure cost.
has_ite_in(Rules, LInt, LEv, HasIte) :-
	(   ( member(R, Rules), contains_ite(R)
	    ; member(C, LInt), contains_ite(C)
	    ; member(C2, LEv), contains_ite(C2) )
	->  HasIte = true
	;   HasIte = false
	).

contains_ite(T) :- compound(T), T = (_ -> _ ; _), !.
contains_ite(T) :- compound(T), arg(_, T, A), contains_ite(A), !.

collect_provenance(Acc, Prov) :-
	findall(prov(N, I, Term, Src),
		( between(1, 21, N), arg(N, Acc, L),
		  nth1(I, L, p(Term, Src)) ),
		Prov).

		 /*******************************
		 *	  clause retrieval	*
		 *******************************/

/* Every retrieval copies. See the module header. */

p_l_int(P, holds(F, T), Body) :-
	arg(5, P, Idx), arg(6, P, All),
	family_lookup(Idx, All, F, Clauses),
	member(Cl, Clauses),
	copy_term(Cl, l_int(holds(F, T), Body)).

p_l_events(P, happens(E, T1, T2), Body) :-
	arg(7, P, Idx), arg(8, P, All),
	family_lookup(Idx, All, E, Clauses),
	member(Cl, Clauses),
	copy_term(Cl, l_events(happens(E, T1, T2), Body)).

p_l_timeless(P, H, Body) :-
	arg(9, P, Idx), arg(10, P, All),
	family_lookup(Idx, All, H, Clauses),
	member(Cl, Clauses),
	copy_term(Cl, l_timeless(H, Body)).

family_lookup(Idx, All, Head, Clauses) :-
	(   nonvar(Head), key_of(Head, Key), Key \== '$var'
	->  (   get_assoc(Key, Idx, L)
	    ->	Clauses = L
	    ;	Clauses = []
	    )
	;   Clauses = All
	).

p_initiated(P, Ev, Fl, Cond) :- p_initiated(P, _, Ev, Fl, Cond).
p_terminated(P, Ev, Fl, Cond) :- p_terminated(P, _, Ev, Fl, Cond).
p_updated(P, Ev, Fl, Change, Cond) :- p_updated(P, _, Ev, Fl, Change, Cond).

/* The indexed forms exist for §I.10.3: a state-change diagram has to say
   *which causal law fired*, not merely that the fluent changed, and an index
   into the source-ordered family is the cheapest stable name for a clause.
   nth1/3 enumerates in list order, so selection order is unchanged.
*/
p_initiated(P, I, Ev, Fl, Cond) :-
	prog_initiated(P, L), nth1(I, L, C), copy_term(C, initiated(Ev, Fl, Cond)).
p_terminated(P, I, Ev, Fl, Cond) :-
	prog_terminated(P, L), nth1(I, L, C), copy_term(C, terminated(Ev, Fl, Cond)).
p_updated(P, I, Ev, Fl, Change, Cond) :-
	prog_updated(P, L), nth1(I, L, C), copy_term(C, updated(Ev, Fl, Change, Cond)).

p_d_pre(P, Conds) :-
	prog_d_pre(P, L), member(C, L), copy_term(C, Conds).

p_d_pre(P, Type, Conds) :-
	prog_d_pre_class(P, L), member(C, L), copy_term(C, Type-Conds).

%!	p_observe(+Prog, ?Events, ?Time) is nondet.
%
%	Resolved by *calling* the program rather than by walking the captured
%	facts, because `observe/2` may be a rule — dining_philosophers_terse.pl
%	generates its observations:
%
%	    observe(L, 2) :- findall(time_to_eat(P), adjacent(_,P,_), L).
%
%	Clause order in the module is source order, so selection order (SP3) is
%	unchanged, and calling a dynamic predicate copies for free.
p_observe(P, Events, Time) :-
	prog_module(P, M),
	catch(M:observe(Events, Time), _, fail).

%!	p_initial_state(+Prog, -Fluents) is nondet.
p_initial_state(P, Fluents) :-
	prog_module(P, M),
	catch(M:initial_state(Fluents), _, fail).

%!	p_reactive_rules(+Prog, -Rules) is det.
%
%	interpreter's `findall(reactive_rule(A,C), (reactive_rule(A,C);
%	reactive_rule(A,C,_)), R0)` — priorities are dropped.
p_reactive_rules(P, Rules) :-
	prog_rules(P, R2),
	prog_rules_pri(P, R3),
	findall(reactive_rule(A, C),
		( member(X, R2), copy_term(X, reactive_rule(A, C))
		; member(Y, R3), copy_term(Y, reactive_rule(A, C, _)) ),
		Rules).

		 /*******************************
		 *	   declarations		*
		 *******************************/

p_action(P, A) :- p_system_action(P, A).
p_action(P, A) :- p_editing_action(P, A).
p_action(P, A) :- p_user_action(P, A).

p_user_action(P, A) :-
	prog_decls(P, decls(_, _, Action1, ActionsL, _, _, _, _)),
	(   member(A0, Action1), copy_term(A0, A)
	;   member(L, ActionsL), member(A0, L), copy_term(A0, A)
	).

p_editing_action(P, A) :-
	(   A = initiate(F) ; A = terminate(F) ; A = update(_Old-_New, F) ),
	once(p_user_fluent_decl(P, F)).

p_event(_, lps_terminate).
p_event(_, lps_terminate(_)).
p_event(P, E) :- p_user_event(P, E).

p_user_event(P, E) :-
	prog_decls(P, decls(_, _, _, _, Event1, EventsL, PrologEventsL, _)),
	(   member(E0, Event1), copy_term(E0, E)
	;   ( member(L, PrologEventsL) ; member(L, EventsL) ),
	    member(E0, L), copy_term(E0, E)
	).

p_fluent(P, F) :- p_system_fluent_t(P, F).
p_fluent(P, F) :- p_external(P, F).
p_fluent(P, F) :- p_user_fluent_decl(P, F).

p_system_fluent_t(_, real_time(_)).
p_system_fluent_t(_, lps_user(_)).
p_system_fluent_t(_, lps_user(_, _)).

p_user_fluent_decl(P, F) :-
	prog_decls(P, decls(Fluent1, FluentsL, _, _, _, _, _, _)),
	(   member(F0, Fluent1), copy_term(F0, F)
	;   member(L, FluentsL), member(F0, L), copy_term(F0, F)
	).

p_prolog_events(P, L) :-
	prog_decls(P, decls(_, _, _, _, _, _, PrologEventsL, _)),
	member(L, PrologEventsL).

p_unserializable(P, L) :-
	prog_decls(P, decls(_, _, _, _, _, _, _, UnserL)),
	member(L, UnserL).

%!	p_intensional(+Prog, +Pred) is semidet.
p_intensional(P, Pred) :-
	nonvar(Pred),
	key_of(Pred, Key), Key \== '$var',
	arg(5, P, Idx),
	get_assoc(Key, Idx, [_|_]), !.

%!	p_macroaction(+Prog, +Event) is semidet.
p_macroaction(P, E) :-
	nonvar(E),
	key_of(E, Key), Key \== '$var',
	arg(7, P, Idx),
	get_assoc(Key, Idx, [_|_]), !.

p_system_action(_, lps_terminate).
p_system_action(_, lps_terminate(_)).
p_system_action(P, A) :- p_external(P, A).

%!	p_external(+Prog, ?Pred) is nondet.
%
%	[verified, §I.4] "if F at T has no fluent declaration but F is a defined
%	Prolog predicate, it is treated as an external extensional fluent;
%	likewise A from T1 to T2 becomes an external basic action."
%
%	"Defined Prolog predicate" means *visible in the program's module*, and
%	that includes built-ins — upstream's version is `current_predicate(F/A)`
%	inside the program module with no built_in filter. This is not a detail:
%	`holds(true,T)` is the engine's own time-slack device, injected by
%	resolve_until_action/4 into composite-event bodies, and it works only
%	because `true/0` is a visible predicate and therefore an external
%	extensional fluent that can simply be called. Narrowing this to the
%	user's own clauses makes every composite event with an implicit end time
%	fail.
%
%	Enumeration (Pred unbound) yields only the user's own predicates:
%	enumerating every visible built-in would be unbounded and no caller
%	wants it. Membership (Pred bound) is the full test.
p_external(P, Pred) :-
	nonvar(Pred), !,
	\+ p_program_predicate(Pred),
	functor(Pred, F, A),
	external_by_name(P, F, A).
p_external(P, Pred) :-
	prog_externals(P, L),
	member(F/A, L),
	functor(Pred, F, A).

/* Memoised, and that is a fidelity improvement as well as a speed one.

   Every fluent query asks this question, so an uncached `current_predicate/1`
   is on the hottest path in the engine. Upstream computes the whole set *once*
   at load time and never revisits it, which means a predicate the program
   creates at run time with uassert/1 is not external there; caching the first
   answer reproduces that, where asking afresh each time would not.
*/
:- dynamic external_cache/3.       % ProgramId, Name/Arity, true|false

external_by_name(P, F, A) :-
	prog_id(P, Id),
	(   external_cache(Id, F/A, Known)
	->  Known == true
	;   (   prog_externals(P, L), memberchk(F/A, L)
	    ->	Answer = true
	    ;	prog_module(P, M), current_predicate(M:F/A)
	    ->	Answer = true
	    ;	Answer = false
	    ),
	    assertz(external_cache(Id, F/A, Answer)),
	    Answer == true
	).

p_d_head(P, H) :- \+ p_system_fluent_t(P, H), \+ p_external(P, H), p_fluent(P, H).
p_d_event(P, H) :- p_action(P, H).
p_d_event(P, H) :- p_event(P, H).

%!	p_user_fluent(+Prog, -Fluent) is nondet.
p_user_fluent(P, F) :-
	findall(Functor/Arity,
		( ( p_user_fluent_decl(P, FF)
		  ; p_l_int(P, holds(FF, _), _) ),
		  functor(FF, Functor, Arity) ),
		L0),
	sort(L0, L),
	member(Functor/Arity, L),
	functor(F, Functor, Arity).

p_has_ite(P) :- prog_setting(P, has_ite, true).

%!	p_call(+Prog, +Goal) is nondet.
%
%	Meta-built-ins resolve their arguments in the module they are called
%	from, so where this call happens decides where `not foo(X)` looks for
%	`foo/1`. The program's own module is that module — and lps_builtins is
%	*imported* into it by new_program_module/2, which is what lets a program
%	call `system_fluent/1` and friends the way upstream's programs do.
%
%	This used to wrap the call in catch/3 and retry an existence_error
%	against lps_builtins by hand. That predates the import, which reaches the
%	same predicates without an exception; the retry could only ever fire for
%	a goal undefined in both, where it re-threw the same error one frame
%	later — after re-running whatever side effects preceded it. Removing it
%	takes catch/3 off the engine's hottest path and stops a program's own
%	existence errors being silently executed twice.
p_call(P, G) :-
	prog_module(P, M),
	call(M:G).

%!	p_clause_src(+Prog, ?Family, ?Index, ?Term, ?Src) is nondet.
%
%	The provenance side table of §I.3, keyed the way the rest of the engine
%	names clauses: by family and position in source order. This is what turns
%	"causal law 2 fired" into a line number, which is the difference between
%	a state-change diagram and a state-change list.
p_clause_src(P, Family, Index, Term, Src) :-
	prov_family(Family, N),
	prog_provenance(P, Prov),
	memberchk_prov(N, Index, Term, Src, Prov).

memberchk_prov(N, I, Term, Src, Prov) :-
	member(prov(N, I, Term, Src), Prov).

%!	p_term_src(+Prog, +Term, -Src) is det.
%
%	Where a clause came from, found by matching the term itself. §I.2.5 wants
%	diagnostics to carry positions so the LSP can place them and offer quick
%	fixes; a diagnostic that says `unknown` is a diagnostic an editor cannot
%	use.
p_term_src(P, Term, Src) :-
	prog_provenance(P, Prov),
	(   member(prov(_, _, T, S), Prov), \+ T \= Term
	->  Src = S
	;   ( prog_setting(P, origin, O) -> Src = src(O, 0, 0, unknown) ; Src = unknown )
	).

prov_family(reactive_rule, 1).
prov_family(reactive_rule_pri, 2).
prov_family(l_int, 3).
prov_family(l_events, 4).
prov_family(l_timeless, 5).
prov_family(initiated, 6).
prov_family(terminated, 7).
prov_family(updated, 8).
prov_family(d_pre, 9).
prov_family(initial_state, 10).
prov_family(observe, 11).

%!	p_program_predicate(+Term) is semidet.
%
%	interpreter:program_predicate/1 — the internal vocabulary itself.
p_program_predicate(T) :- program_predicate_(T).

program_predicate_(actions(_)).
program_predicate_(unserializable(_)).
program_predicate_(action(_)).
program_predicate_(d_pre(_)).
program_predicate_(prolog_events(_)).
program_predicate_(events(_)).
program_predicate_(event(_)).
program_predicate_(fluents(_)).
program_predicate_(fluent(_)).
program_predicate_(initial_state(_)).
program_predicate_(initiated(_, _, _)).
program_predicate_(l_events(_, _)).
program_predicate_(l_int(_, _)).
program_predicate_(l_timeless(_, _)).
program_predicate_(observe(_, _)).
program_predicate_(reactive_rule(_, _)).
program_predicate_(reactive_rule(_, _, _)).
program_predicate_(terminated(_, _, _)).
program_predicate_(updated(_, _, _, _)).
program_predicate_(maxTime(_)).
program_predicate_(maxRealTime(_)).
program_predicate_(simulatedRealTimePerCycle(_)).
program_predicate_(simulatedRealTimeBeginning(_)).
program_predicate_(minCycleTime(_)).
program_predicate_(display(_, _)).
program_predicate_(display3d(_, _)).
program_predicate_(achieve(_)).
program_predicate_(defaults(_)).

		 /*******************************
		 *	   static checks	*
		 *******************************/

%	A deliberately small subset of interpreter:check_syntax/2 — the checks
%	that catch real mistakes without rejecting corpus programs that the old
%	engine accepts. Everything is a diag/5 term (§I.2.5).
check_program(P, Diags) :-
	findall(D, program_diag(P, D), Diags).

program_diag(P, D) :-
	prog_d_pre_class(P, Class),
	member(both-_, Class),
	prog_setting(P, options, Options),
	memberchk(non_prospective, Options),
	diag(error, nextstate_dependency_with_non_prospective,
	     unknown,
	     'a precondition refers to the next state but option non_prospective is set',
	     D).
program_diag(P, D) :-
	p_l_int(P, H, B),
	\+ ( nonvar(H), H = holds(_, _) ),
	format(atom(M), 'not a valid intensional predicate: ~q', [H]),
	p_term_src(P, l_int(H, B), Src),
	diag(error, bad_l_int_head, Src, M, D).
program_diag(P, D) :-
	p_l_events(P, H, B),
	\+ ( nonvar(H), H = happens(_, _, _) ),
	format(atom(M), 'not a valid composite event predicate: ~q', [H]),
	p_term_src(P, l_events(H, B), Src),
	diag(error, bad_l_events_head, Src, M, D).
program_diag(P, D) :-
	prog_module(P, M),
	catch(M:achieve(_), _, fail),
	\+ prog_setting(P, engine, planning),
	p_term_src(P, achieve(_), Src),
	diag(error, achieve_without_planning_mode, Src,
	     'achieve/1 requires `:- lps_engine(planning, Options).` — under the \c
	      default reactive engine it has no meaning (§I.7.2)', D).
program_diag(P, D) :-
	prog_rules(P, []), prog_rules_pri(P, []),
	\+ ( prog_module(P, M2), catch(M2:achieve(_), _, fail) ),
	( prog_setting(P, origin, O) -> Src = src(O, 1, 0, program) ; Src = unknown ),
	diag(warning, no_reactive_rules, Src, 'no reactive rules are present', D).

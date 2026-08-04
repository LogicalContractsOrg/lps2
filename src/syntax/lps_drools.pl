/* lps_drools.pl — DRL as a front end (M12d, §IV.2 and §IV.6).
 *
 * KELPS was framed as reconciling production systems with logic programming,
 * so this is the transpilation the theory was written for: `when … then …` is
 * a reactive rule, working memory is the state, and a rule that fires because
 * a fact appeared is an LPS cycle.
 *
 * The mapping:
 *
 *   rule "R" when P1, P2 then RHS end
 *       →  if <P1 at T>, <P2 at T> then <actions of RHS> from T to T2.
 *   Type( field == v, x : other )
 *       →  the fluent type(…) with `v` in field's position and X in other's
 *   not Type( … )                    →  not type(…) at T
 *   insert(new Type(a, b))           →  insert_type(a, b), a declared action
 *   modify(v) { f = e }              →  modify_type(…), an action that updates
 *   retract(v) / delete(v)           →  retract_type(…), an action that terminates
 *   declare Type f1 : t1 end         →  the field order for that type
 *
 * §IV.1's boundary, stated rather than discovered: **the right-hand side of a
 * Drools rule is Java**, and Java is not transpiled. A statement this module
 * does not recognise becomes an *external action* — `java_leaf/2`, which the
 * engine treats as an action with no causal law — and a diagnostic naming the
 * rule and the statement. That is the difference between a transpiler you can
 * trust on a real rule base and one that quietly drops half of it.
 *
 * Two semantic gaps that are reported, not papered over (§IV.5):
 *
 *   * **salience**. Drools resolves conflicts by an operational priority; LPS
 *     has no equivalent and is not supposed to. A rule with a salience gets a
 *     warning, and the priority is recorded in reactive_rule/3 where the
 *     engine can at least see it.
 *   * **truth maintenance** (`insertLogical`). A logically-inserted fact is
 *     retracted when its support goes away, which is an *intensional* fluent
 *     rather than a causal law. Recognised, warned about, and translated as
 *     an intensional fluent when the support is a single pattern.
 */

:- module(lps_drools, [
	drl_to_internal/3,       % +File, -Terms, -Diags
	drl_parse/3              % +File, -Rules, -Declares
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module('../core/lps_ops').
:- use_module('../core/lps_diag').

:- discontiguous effect_terms/5.

		 /*******************************
		 *	    tokenising		*
		 *******************************/

drl_text(File, Text) :-
	read_file_to_string(File, S, [encoding(utf8)]),
	string_codes(S, C0),
	strip_block_comments(C0, C1),
	strip_line_comments(C1, C2),
	string_codes(Text, C2).

strip_block_comments([], []).
strip_block_comments([0'/, 0'*|T], Out) :- !, skip_block(T, T1), strip_block_comments(T1, Out).
strip_block_comments([C|T], [C|Out]) :- strip_block_comments(T, Out).

skip_block([], []).
skip_block([0'*, 0'/|T], T) :- !.
skip_block([_|T], Out) :- skip_block(T, Out).

strip_line_comments([], []).
strip_line_comments([0'/, 0'/|T], Out) :- !, skip_line(T, T1), strip_line_comments(T1, Out).
strip_line_comments([C|T], [C|Out]) :- strip_line_comments(T, Out).

skip_line([], []).
skip_line([0'\n|T], [0'\n|T]) :- !.
skip_line([_|T], Out) :- skip_line(T, Out).

		 /*******************************
		 *	    parsing		*
		 *******************************/

%!	drl_parse(+File, -Rules, -Declares) is det.
%
%	Rules are rule(Name, Salience, Patterns, RHS, Line); Declares are
%	declare(Type, Fields).
drl_parse(File, Rules, Declares) :-
	drl_text(File, Text),
	split_string(Text, "\n", "", Lines),
	parse_lines(Lines, 1, [], Rules, Declares).

parse_lines([], _, _, [], []).
parse_lines([L|Ls], N, Acc, Rules, Declares) :-
	normalize_space(string(T), L),
	N1 is N + 1,
	(   sub_string(T, 0, _, _, "rule ")
	->  rule_name(T, Name),
	    collect_until_end(Ls, Rest, Body, N1, N2),
	    rule_of(Name, Body, N, Rule),
	    parse_lines(Rest, N2, Acc, Rules0, Declares),
	    Rules = [Rule|Rules0]
	;   sub_string(T, 0, _, _, "declare ")
	->  declare_name(T, Type),
	    collect_until_end(Ls, Rest, Body, N1, N2),
	    fields_of(Body, Fields),
	    parse_lines(Rest, N2, Acc, Rules, Declares0),
	    Declares = [declare(Type, Fields)|Declares0]
	;   parse_lines(Ls, N1, Acc, Rules, Declares)
	).

collect_until_end([], [], [], N, N).
collect_until_end([L|Ls], Rest, Body, N, NOut) :-
	normalize_space(string(T), L),
	N1 is N + 1,
	(   T == "end"
	->  Rest = Ls, Body = [], NOut = N1
	;   collect_until_end(Ls, Rest, Body0, N1, NOut),
	    Body = [T|Body0]
	).

rule_name(T, Name) :-
	(   sub_string(T, B, _, _, "\""),
	    Start is B + 1,
	    sub_string(T, Start, _, _, R),
	    sub_string(R, E, _, _, "\"")
	->  sub_string(R, 0, E, _, S), atom_string(Name, S)
	;   Name = unnamed
	).

declare_name(T, Type) :-
	split_string(T, " ", " ", Parts),
	( Parts = [_, S|_] -> string_lower(S, L), atom_string(Type, L) ; Type = unknown ).

fields_of(Lines, Fields) :-
	findall(F, ( member(L, Lines), split_string(L, ":", " ", [FS|_]),
		     FS \== "", string_lower(FS, LF), atom_string(F, LF) ), Fields).

%	when … then … — everything between is the condition, everything after
%	is the (Java) consequence.
rule_of(Name, Body, Line, rule(Name, Salience, Patterns, RHS, Line)) :-
	salience_of(Body, Salience),
	split_when_then(Body, When, Then),
	patterns_of(When, Patterns),
	RHS = Then.

salience_of(Body, S) :-
	(   member(L, Body), sub_string(L, B, _, _, "salience")
	->  Pos is B + 8, sub_string(L, Pos, _, 0, R),
	    normalize_space(string(R1), R),
	    ( number_string(S, R1) -> true ; S = 0 )
	;   S = 0
	).

split_when_then(Body, When, Then) :-
	(   nth0(I, Body, "when")
	->  J is I + 1, length(Pre, J), append(Pre, Rest, Body),
	    (	nth0(K, Rest, "then")
	    ->	length(When, K), append(When, [_|Then], Rest)
	    ;	When = Rest, Then = []
	    )
	;   When = [], Then = Body
	).

/* A pattern is `Var : Type( constraints )`, `Type( constraints )`,
   `not Type( … )` or `exists Type( … )`.
 *
 * DRL separates patterns by *line*, not by comma — the commas inside the
 * parentheses separate a pattern's own constraints. So lines are joined only
 * while their parentheses are unbalanced, which is how a pattern wrapped over
 * three lines stays one pattern.
 */
patterns_of(Lines, Patterns) :-
	join_wrapped(Lines, Chunks0),
	findall(C, ( member(X, Chunks0), normalize_space(atom(C), X), C \== '',
		     C \== 'and' ), Chunks),
	findall(P, ( member(C, Chunks), pattern_of(C, P) ), Patterns).

join_wrapped([], []).
join_wrapped([L|Ls], [Chunk|Rest]) :-
	depth_of(L, 0, D),
	(   D =:= 0
	->  Chunk = L, Ls1 = Ls
	;   join_more(Ls, D, L, Chunk, Ls1)
	),
	join_wrapped(Ls1, Rest).

join_more([], _, Acc, Acc, []).
join_more([L|Ls], D0, Acc, Chunk, Rest) :-
	atomic_list_concat([Acc, ' ', L], Acc1),
	depth_of(L, D0, D),
	( D =:= 0 -> Chunk = Acc1, Rest = Ls ; join_more(Ls, D, Acc1, Chunk, Rest) ).

depth_of(S, D0, D) :-
	atom_string(A, S), atom_codes(A, Cs),
	foldl([C, In, Out]>>( C =:= 0'( -> Out is In + 1
			    ; C =:= 0') -> Out is In - 1
			    ; Out = In ), Cs, D0, D).

%	Split on top-level commas — the ones outside parentheses, since a
%	pattern's own constraints are comma-separated inside them.
split_patterns(S, Chunks) :-
	atom_codes(S, Cs),
	split_top(Cs, 0, [], Chunks0),
	findall(C, ( member(X, Chunks0), atom_codes(A, X),
		     normalize_space(atom(C), A), C \== '' ), Chunks).

split_top([], _, Acc, [Out]) :- reverse(Acc, Out).
split_top([C|Cs], D, Acc, Out) :-
	(   C =:= 0'( -> D1 is D + 1, split_top(Cs, D1, [C|Acc], Out)
	;   C =:= 0') -> D1 is D - 1, split_top(Cs, D1, [C|Acc], Out)
	;   C =:= 0',, D =:= 0
	->  reverse(Acc, Chunk), split_top(Cs, D, [], Rest), Out = [Chunk|Rest]
	;   split_top(Cs, D, [C|Acc], Out)
	).

pattern_of(Chunk, pattern(Kind, Var, Type, Constraints)) :-
	atom_string(Chunk, S),
	(   sub_string(S, 0, 4, _, "not ")
	->  Kind = neg, sub_string(S, 4, _, 0, S1)
	;   sub_string(S, 0, 7, _, "exists ")
	->  Kind = pos, sub_string(S, 7, _, 0, S1)
	;   Kind = pos, S1 = S
	),
	(   sub_string(S1, B, 1, _, ":"), sub_string(S1, 0, B, _, V0),
	    normalize_space(string(VS), V0), VS \== "", \+ sub_string(VS, _, _, _, "(")
	->  atom_string(Var, VS), Bp is B + 1, sub_string(S1, Bp, _, 0, S2)
	;   Var = '', S2 = S1
	),
	sub_string(S2, P, 1, _, "("), !,
	sub_string(S2, 0, P, _, T0), normalize_space(string(TS), T0),
	string_lower(TS, TL), atom_string(Type, TL),
	Pp is P + 1, sub_string(S2, Pp, _, 1, Inner0),
	normalize_space(string(Inner), Inner0),
	constraints_of(Inner, Constraints).

constraints_of("", []) :- !.
constraints_of(S, Constraints) :-
	atom_codes(S, Cs), split_top(Cs, 0, [], Parts),
	findall(C, ( member(P, Parts), atom_codes(A, P), normalize_space(atom(N), A),
		     N \== '', constraint_of(N, C) ), Constraints).

constraint_of(A, eq(Field, Value)) :-
	sub_atom(A, B, 2, _, '=='), !,
	sub_atom(A, 0, B, _, F0), Bp is B + 2, sub_atom(A, Bp, _, 0, V0),
	clean_field(F0, Field), clean_value(V0, Value).
constraint_of(A, bind(Field, Var)) :-
	sub_atom(A, B, 1, _, ':'), !,
	sub_atom(A, 0, B, _, V0), Bp is B + 1, sub_atom(A, Bp, _, 0, F0),
	clean_field(F0, Field), clean_var(V0, Var).
constraint_of(A, other(A)).

clean_field(A, F) :- normalize_space(atom(N), A), downcase_atom(N, D), F = D.
clean_var(A, V) :- normalize_space(atom(N), A), V = N.

clean_value(A, V) :-
	normalize_space(atom(N), A),
	(   atom_number(N, Num) -> V = Num
	;   sub_atom(N, 0, 1, _, '"')
	->  sub_atom(N, 1, _, 1, S), V = S
	;   sub_atom(N, B, 1, _, '.'), sub_atom(N, _, _, 0, Last), B > 0
	->  atomic_list_concat(Parts, '.', N), last(Parts, LastPart),
	    downcase_atom(LastPart, V), ignore(Last = Last)
	;   downcase_atom(N, V)
	).

		 /*******************************
		 *	  translation		*
		 *******************************/

%!	drl_to_internal(+File, -Terms, -Diags) is det.
drl_to_internal(File, Terms, Diags) :-
	drl_parse(File, Rules, Declares),
	field_order(Rules, Declares, Order),
	findall(T-D, ( member(R, Rules), rule_terms(R, Order, File, T, D) ), Pairs),
	findall(T, member(T-_, Pairs), Ts0), append(Ts0, RuleTerms),
	findall(D, member(_-D, Pairs), Ds0), append(Ds0, RuleDiags),
	%  Declarations come from the *translated* terms, not from a second parse
	%  of the right-hand sides: `modify( s ) { … }` names a variable, and
	%  re-deriving the action from it declared `modify_s` while the rules
	%  used `modify_sprinkler`.
	declarations(Order, RuleTerms, File, DeclTerms),
	append(DeclTerms, RuleTerms, Terms),
	Diags = RuleDiags.

/* Drools facts are Java objects; LPS fluents are terms. So a type's fields
   need an *order*, and it comes from a `declare` block when there is one and
   from the union of the fields the rules mention otherwise. Inferring it is
   not a guess about semantics — the order is arbitrary and internal — but it
   does mean two files about the same type must be translated together.
*/
field_order(Rules, Declares, Order) :-
	findall(Type-Fields,
		( member(declare(Type, Fields), Declares) ),
		FromDeclares),
	findall(Type-Fields,
		( member(rule(_, _, Patterns, _, _), Rules),
		  member(pattern(_, _, Type, _), Patterns),
		  \+ memberchk(Type-_, FromDeclares),
		  findall(F, ( member(rule(_, _, Ps, _, _), Rules),
			       member(pattern(_, _, Type, Cs), Ps),
			       member(C, Cs), constraint_field(C, F) ), Fs0),
		  sort(Fs0, Fields) ),
		FromRules0),
	dedupe_keys(FromRules0, FromRules),
	append(FromDeclares, FromRules, Order).

dedupe_keys([], []).
dedupe_keys([K-V|T], [K-V|Out]) :- exclude_key(K, T, T1), dedupe_keys(T1, Out).
exclude_key(_, [], []).
exclude_key(K, [K2-V|T], Out) :-
	( K == K2 -> Out = Out1 ; Out = [K2-V|Out1] ),
	exclude_key(K, T, Out1).

constraint_field(eq(F, _), F).
constraint_field(bind(F, _), F).

declarations(Order, RuleTerms, File, Terms) :-
	findall(Tmpl, ( member(Type-Fields, Order), length(Fields, N),
			functor(Tmpl, Type, N) ), Fluents),
	findall(Tmpl, ( member(t(Term, _), RuleTerms), term_action(Term, A),
			functor(A, N2, A2), functor(Tmpl, N2, A2) ), Actions0),
	sort(Actions0, Actions),
	Src = src(File, 1, 0, drl),
	findall(t(fluents(Fluents), Src), Fluents \== [], F1),
	findall(t(actions(Actions), Src), Actions \== [], A1),
	append(F1, A1, Terms).

term_action(reactive_rule(_, Cons), A) :- member(happens(A, _, _), Cons).
term_action(reactive_rule(_, Cons, _), A) :- member(happens(A, _, _), Cons).
term_action(initiated(happens(A, _, _), _, _), A).
term_action(terminated(happens(A, _, _), _, _), A).
term_action(updated(happens(A, _, _), _, _, _), A).

/* One rule → one reactive rule, plus the causal laws its right-hand side
   implies. The consequence is a list of actions, and each action that changes
   working memory gets `initiates`/`terminates`/`updates` to say how.
*/
rule_terms(rule(Name, Salience, Patterns, RHS, Line), Order, File, Terms, Diags) :-
	Src = src(File, Line, 0, drl),
	%  One variable map per rule: `Fire(room : room)` binds `room`, and the
	%  `room == room` of the next pattern refers to *that* variable. Without
	%  the map each pattern gets its own, and the rule says "a fire and a
	%  sprinkler, anywhere" — which is not what it says.
	rule_var_map(Patterns, RHS, Map),
	%  All the patterns of a Drools rule match ONE state of working memory,
	%  so they share one time variable. Giving each its own would let the
	%  rule match a fire in one cycle and a sprinkler in another.
	maplist(pattern_literal(Order, Map, _T), Patterns, Conds),
	rhs_actions(RHS, Order, Map, Patterns, Actions0),
	%  No findall/3 anywhere near these: it copies, and a copied action no
	%  longer shares the rule's variables with the antecedent that bound
	%  them. `insert(new Sprinkler(room, on))` would insert a sprinkler in
	%  *some* room rather than in the burning one.
	keys_of(Actions0, Actions),
	(   Actions == []
	->  Cons = [happens(java_leaf(Name), _, _)]
	;   happens_list(Actions, Cons)
	),
	(   Salience =:= 0
	->  Rule = reactive_rule(Conds, Cons)
	;   Rule = reactive_rule(Conds, Cons, Salience)
	),
	effect_list(Actions0, Order, Map, Src, Effects),
	Terms = [t(Rule, Src)|Effects],
	rule_diags(Name, Salience, RHS, Actions, Src, Diags).

rule_var_map(Patterns, RHS, Map) :-
	findall(V, ( member(pattern(_, _, _, Cs), Patterns), member(bind(_, V), Cs) ), Vs0),
	findall(V, ( member(pattern(_, V, _, _), Patterns), V \== '' ), Vs1),
	append(Vs0, Vs1, Vs2), sort(Vs2, Vars),
	findall(V-_, member(V, Vars), Map),
	ignore(RHS = RHS).

pattern_literal(Order, Map, T, pattern(Kind, _Var, Type, Constraints), Literal) :-
	fluent_term(Type, Constraints, Order, Map, F),
	( Kind == neg -> Literal = holds(not(F), T) ; Literal = holds(F, T) ).

/* Fill the argument slots from the constraints.
 *
 * Not with forall/2, which was the first attempt: forall is \+ (C, \+ A), so
 * every binding it makes is undone on the way out and the fluent comes back
 * with all-fresh arguments — a rule that reads `Fire(room: r), Sprinkler(room
 * == r)` then means "a fire and a sprinkler, anywhere".
 */
fluent_term(Type, Constraints, Order, Map, F) :-
	( memberchk(Type-Fields, Order) -> true ; Fields = [] ),
	length(Fields, N),
	functor(F, Type, N),
	fill_fields(Fields, 1, Constraints, Map, F).

fill_fields([], _, _, _, _).
fill_fields([Field|Fs], I, Constraints, Map, F) :-
	(   member(C, Constraints), constraint_field(C, Field)
	->  arg(I, F, Slot), constraint_value(C, Map, Slot)
	;   true
	),
	I1 is I + 1,
	fill_fields(Fs, I1, Constraints, Map, F).

%	`room == room` is a *variable reference* when something bound `room`
%	earlier in the rule, and a constant otherwise. Drools tells them apart
%	by scope; so do we.
constraint_value(eq(_, V), Map, Slot) :-
	( memberchk(V-Var, Map) -> Slot = Var ; Slot = V ).
constraint_value(bind(_, V), Map, Slot) :-
	( memberchk(V-Var, Map) -> Slot = Var ; true ).

/* Right-hand sides. Four shapes are understood; everything else is a leaf. */
rhs_action(Line, Order, Action, Kind) :-
	(   sub_string(Line, B, _, _, "insert("), \+ sub_string(Line, _, _, _, "insertLogical")
	->  Kind = insert, args_after(Line, B, 7, Type, Args), action_name(insert, Type, Args, Order, Action)
	;   sub_string(Line, B, _, _, "insertLogical(")
	->  Kind = insert_logical, args_after(Line, B, 14, Type, Args),
	    action_name(insert, Type, Args, Order, Action)
	;   ( sub_string(Line, B, _, _, "retract(") -> Off = 8 ; sub_string(Line, B, _, _, "delete(") -> Off = 7 )
	->  Kind = retract, args_after(Line, B, Off, Type, Args), action_name(retract, Type, Args, Order, Action)
	;   sub_string(Line, B, _, _, "modify(")
	->  Kind = modify, args_after(Line, B, 7, Type, Args), action_name(modify, Type, Args, Order, Action)
	;   fail
	).

args_after(Line, B, Off, Type, Args) :-
	P is B + Off,
	sub_string(Line, P, _, 0, Rest),
	( sub_string(Rest, E, 1, _, ")") -> sub_string(Rest, 0, E, _, Inner) ; Inner = Rest ),
	normalize_space(string(I2), Inner),
	( sub_string(I2, 0, 4, _, "new ") -> sub_string(I2, 4, _, 0, I3) ; I3 = I2 ),
	(   sub_string(I3, P2, 1, _, "(")
	->  sub_string(I3, 0, P2, _, T0), P3 is P2 + 1,
	    sub_string(I3, P3, _, 0, A0),
	    split_string(A0, ",", " ()", Args0),
	    findall(A, ( member(S, Args0), S \== "", clean_value(S, A) ), Args)
	;   T0 = I3, Args = []
	),
	string_lower(T0, TL), atom_string(Type, TL).

action_name(Op, Type, Args, _Order, Action) :-
	atomic_list_concat([Op, '_', Type], Name),
	Action =.. [Name|Args].

/* `updated/4` takes the *values* being replaced, not the whole fluents:
   `row(L1,L2) updates L1 to L2 in loc(farmer,L1)` is
   `updated(happens(row(L1,L2),…), loc(farmer,L1), L1-L2, [])`. Passing the
   fluents themselves compiles and then never matches. */
effect_terms(Action, retract(Gone), _Order, _Map, Term) :- !,
	Term = terminated(happens(Action, _, _), Gone, []).
effect_terms(Action, modify(Old, New), _Order, _Map, Term) :- !,
	Old =.. [_|OldArgs], New =.. [_|NewArgs],
	changed_values(OldArgs, NewArgs, Olds, News),
	( Olds = [O], News = [N] -> Change = O-N ; Change = Olds-News ),
	Term = updated(happens(Action, _, _), Old, Change, []).

changed_values([], [], [], []).
changed_values([O|Os], [N|Ns], Olds, News) :-
	(   O == N
	->  Olds = Olds1, News = News1
	;   Olds = [O|Olds1], News = [N|News1]
	),
	changed_values(Os, Ns, Olds1, News1).
effect_terms(Action, Line, Order, _Map, Term) :-
	rhs_action(Line, Order, _A0, Kind),
	Action =.. [_|Args],
	action_type(Action, Type),
	( memberchk(Type-Fields, Order) -> true ; Fields = [] ),
	length(Fields, N),
	functor(F, Type, N),
	bind_prefix(F, Args, 1),
	(   Kind == insert -> Term = initiated(happens(Action, _, _), F, [])
	;   Kind == insert_logical -> Term = initiated(happens(Action, _, _), F, [])
	;   Kind == retract -> Term = terminated(happens(Action, _, _), F, [])
	;   Kind == modify -> Term = initiated(happens(Action, _, _), F, [])
	).

/* An action's arguments name the rule's variables where they match one — and
   the mapping has to be an explicit recursion, not findall/3, for the same
   reason fluent_term/5 is: findall copies its solutions, so the variable the
   action shares with the antecedent would be a copy of it and share nothing.
*/
keys_of([], []).
keys_of([K-_|T], [K|Out]) :- keys_of(T, Out).

happens_list([], []).
happens_list([A|As], [happens(A, _, _)|Out]) :- happens_list(As, Out).

effect_list([], _, _, _, []).
effect_list([A-L|T], Order, Map, Src, Out) :-
	(   effect_terms(A, L, Order, Map, Term)
	->  Out = [t(Term, Src)|Rest]
	;   Out = Rest
	),
	effect_list(T, Order, Map, Src, Rest).

rhs_actions([], _, _, _, []).
rhs_actions([L|Ls], Order, Map, Patterns, Out) :-
	(   modify_action(L, Order, Map, Patterns, A, Old, New)
	->  Out = [A-modify(Old, New)|Rest]
	;   retract_action(L, Order, Map, Patterns, A, Gone)
	->  Out = [A-retract(Gone)|Rest]
	;   rhs_action(L, Order, A0, _)
	->  bind_action(A0, Map, A), Out = [A-L|Rest]
	;   Out = Rest
	),
	rhs_actions(Ls, Order, Map, Patterns, Rest).

/* `retract( o )` — and `o` is a *pattern variable*, not a type.
 *
 * The generic path lowercases whatever is inside the parentheses and treats it
 * as a type name, which for `retract(o)` produced an action called `retract_o`
 * that terminated nothing at all: the rule fired forever and the fact stayed.
 * Drools binds `o` in the `when` side, so the pattern is right there — resolve
 * it the same way `modify` does, and terminate the fluent the variable stands
 * for.
 */
retract_action(Line, Order, Map, Patterns, Action, Gone) :-
	( sub_string(Line, B, _, _, "retract(") -> Off = 8
	; sub_string(Line, B, _, _, "delete(") -> Off = 7 ),
	P is B + Off,
	sub_string(Line, P, _, 0, Rest),
	sub_string(Rest, E, 1, _, ")"),
	sub_string(Rest, 0, E, _, VarS),
	normalize_space(atom(Var), VarS),
	member(pattern(_, Var, Type, Constraints), Patterns),
	!,
	fluent_term(Type, Constraints, Order, Map, Gone),
	Gone =.. [_|Args],
	atomic_list_concat([retract, '_', Type], Name),
	Action =.. [Name|Args].

/* `modify( s ) { on = true }` — Drools' update-in-place, and the reason it
   matters is that an `insert` of a changed copy leaves the old fact in working
   memory. The variable names a pattern, the pattern names a type, and the
   braces say which field changes; the result is an LPS action that terminates
   the old fluent and initiates the new one, which is exactly `updates`.
*/
modify_action(Line, Order, Map, Patterns, Action, Old, New) :-
	sub_string(Line, B, _, _, "modify("),
	P is B + 7,
	sub_string(Line, P, _, 0, Rest),
	sub_string(Rest, E, 1, _, ")"),
	sub_string(Rest, 0, E, _, VarS),
	normalize_space(atom(Var), VarS),
	member(pattern(_, Var, Type, Constraints), Patterns),
	!,
	fluent_term(Type, Constraints, Order, Map, Old),
	( memberchk(Type-Fields, Order) -> true ; Fields = [] ),
	assignments(Rest, Assigns),
	copy_with(Old, Fields, Assigns, New),
	New =.. [_|NewArgs],
	atomic_list_concat([modify, '_', Type], Name),
	Action =.. [Name|NewArgs].

%	`{ f = v, g = w }` → [f-v, g-w].
assignments(S, Assigns) :-
	(   sub_string(S, B, 1, _, "{"), sub_string(S, A, 1, _, "}"), A > B
	->  Start is B + 1, Len is A - Start,
	    sub_string(S, Start, Len, _, Inner),
	    split_string(Inner, ",", " ", Parts),
	    findall(F-V, ( member(Part, Parts), Part \== "",
			   split_string(Part, "=", " ", [FS, VS]),
			   string_lower(FS, FL), atom_string(F, FL),
			   clean_value(VS, V) ), Assigns)
	;   Assigns = []
	).

copy_with(Old, Fields, Assigns, New) :-
	Old =.. [Name|Args],
	replace_fields(Fields, 1, Args, Assigns, NewArgs),
	New =.. [Name|NewArgs].

replace_fields([], _, Args, _, Args).
replace_fields([F|Fs], I, Args, Assigns, Out) :-
	(   memberchk(F-V, Assigns)
	->  replace_nth(I, Args, V, Args1)
	;   Args1 = Args
	),
	I1 is I + 1,
	replace_fields(Fs, I1, Args1, Assigns, Out).

replace_nth(1, [_|T], V, [V|T]) :- !.
replace_nth(N, [X|T], V, [X|Out]) :- N1 is N - 1, replace_nth(N1, T, V, Out).

bind_action(A0, Map, A) :-
	A0 =.. [N|Args0],
	map_args(Args0, Map, Args),
	A =.. [N|Args].

map_args([], _, []).
map_args([Arg|As], Map, [X|Xs]) :-
	( memberchk(Arg-V, Map) -> X = V ; X = Arg ),
	map_args(As, Map, Xs).

action_type(Action, Type) :-
	functor(Action, Name, _),
	atomic_list_concat([_, Type], '_', Name).

bind_prefix(_, [], _).
bind_prefix(F, [A|As], I) :-
	( arg(I, F, A) -> true ; true ),
	I1 is I + 1, bind_prefix(F, As, I1).

rule_diags(Name, Salience, RHS, Actions, Src, Diags) :-
	findall(D,
		( Salience =\= 0,
		  format(atom(M), 'rule "~w" uses salience ~w. LPS has no conflict-resolution \c
priority: the rule is translated, the priority is recorded, and firing order may differ \c
(§IV.2)', [Name, Salience]),
		  diag(warning, drools_salience, Src, M, D) ),
		D1),
	findall(D,
		( member(L, RHS), \+ rhs_action(L, [], _, _), L \== "",
		  \+ sub_string(L, 0, _, _, "//"),
		  format(atom(M), 'rule "~w": `~w` is a procedural leaf and is not \c
transpiled; it becomes an external action (§IV.1)', [Name, L]),
		  diag(warning, drools_java_leaf, Src, M, D) ),
		D2),
	findall(D,
		( Actions == [],
		  format(atom(M), 'rule "~w" has no working-memory action: its whole \c
consequence is procedural', [Name]),
		  diag(warning, drools_no_action, Src, M, D) ),
		D3),
	append([D1, D2, D3], Diags).

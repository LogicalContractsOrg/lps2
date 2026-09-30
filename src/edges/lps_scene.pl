/* lps_scene.pl — geometry, computed rather than guessed (§I.10.4e).
 *
 * The first version of "Animate in 2D" asked a language model for `display/2`
 * clauses with coordinates in them. Models are good at knowing that a goat
 * belongs on a river bank and bad at arithmetic over a canvas, so what came
 * back was plausible and overlapping: three animals at the same point, a label
 * off the edge, a river drawn over the farmer. Telling the model to try harder
 * is not a fix; the model is being asked to do the one part of the job that is
 * mechanical.
 *
 * So the work splits, which is the shape the literature converged on too —
 * DiagrammerGPT's "diagram plan", the parse-then-place decomposition, and the
 * decoupled logical-artifact-then-renderer patent all separate *what is in the
 * picture* from *where it goes*:
 *
 *   stage 1  the model produces a **plan**: which containers exist, which
 *            things live in them, which fluent template puts a thing in a
 *            container, what each thing looks like. No coordinates at all.
 *
 *   stage 2  this file lays it out. Box flow — Yoga's model rather than
 *            Cassowary's — because the plan expresses containment and order,
 *            which is exactly what a flexbox consumes, and because boxes that
 *            flow cannot overlap by construction. Cassowary would be the right
 *            answer if the model were emitting alignment constraints; it is
 *            not, and asking it to would move the hard part back.
 *
 * The output is ordinary `display/2` clauses over a generated slot table, so
 * the program stays readable, editable and self-contained: nothing at run time
 * calls back into this file.
 *
 * ## Four shapes, not two
 *
 * A plan says one or more of four things; each was added because without it a
 * whole kind of program could not be drawn:
 *
 *   * **containers and members** — a fluent that says *where a thing is*:
 *     `loc(Object, Where)`, `at(Robot, Room)`. Static geometry: a grid of
 *     slots, one per (container, thing) pair.
 *   * **gauges** — a fluent that says *what value something has*:
 *     `heating(on)`, `balance(alice, 100)`.
 *   * **lamps** — a fluent that is simply true or false: `alerted`, `stopped`.
 *     A gauge with no `value_var`: the box is there while it holds and gone
 *     while it does not, under a caption that stays. Without it a program
 *     whose state is flags had NO shape it could be drawn with, and the
 *     animation of `underground.lps` showed two of its five fluents.
 *   * **stacks** — a fluent that says *what a thing is standing on*:
 *     `on(Block, Support)`, where the support is another thing of the same
 *     kind. Read as containers, `on(a,b), on(b,c), …` draws seven boxes each
 *     holding one small square, every block appears twice — once as a
 *     container and once as a thing — and a tower is nowhere on the screen.
 *
 * A stack cannot use the slot table, and that is the interesting part. How high
 * a block is drawn depends on how many blocks are underneath it, which changes
 * every cycle, so the geometry cannot be precomputed at all: what is generated
 * is a small *recursion over the state*, the same one `examples/start/blocks3d.lps`
 * writes by hand. `state/1` is the engine's own view of the current state
 * (src/core/lps_builtins.pl) and the scene layer points it at the cycle being
 * drawn, so the tower in the picture is the tower at that cycle.
 *
 * A plan that calls a support relation "containers" is *promoted* rather than
 * rejected — see promote_stacks/8. A model that has not read this file's prompt
 * still gets a tower.
 */

:- module(lps_scene, [
	scene_clauses/3,         % +Plan (dict), -Text, -Diags
	scene_clauses/4,         % +Plan (dict), +Kind, -Text, -Diags
	scene_clauses/5,         % +Plan, +Kind, +Options, -Text, -Diags
	scene_clauses/6          % +Plan, +Kind, +Options, -Text, -Diags, -Drawn
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(library(pairs)).
:- use_module('../core/lps_diag').

/* Geometry constants. One cell holds one thing; a group is a padded grid of
   cells with room for its title. Everything else follows. */
cell(46).
gap(10).
pad(16).
title_h(20).
group_gap(28).
max_cols(4).
/*  A pane is wider than it is tall, and `fit()` in the 2D renderer scales the
    whole scene to fit — so what decides how big anything *looks* is not the
    scene's size but its aspect ratio. A scene shaped 1:6 is drawn at a sixth of
    the scale a squarish one would get. Hence a target, and a count below which
    the model's own axis is left alone. */
target_ratio(1.4).
wrap_from(5).

/*  A pile's own measurements. `pitch_y` is one cell plus the gap between two
    blocks in a tower; `pitch_x` the same between two towers. The 3D set is the
    same arrangement in metres-ish units, chosen so a seven-block tower sits
    inside a default camera. */
pitch_y(52).
pitch_x(56).
floor_h(12).
cell3(1.6).
pitch3_y(1.8).
pitch3_x(2.2).

%!	scene_clauses(+Plan, -Text, -Diags) is det.
%
%	Plan is the dict described in the module header. Text is Prolog source:
%	a slot table, a `display(timeless, …)` backdrop and one `display/2` rule
%	per layer.
scene_clauses(Plan, Text, Diags) :- scene_clauses(Plan, twod, Text, Diags).

%!	scene_clauses(+Plan, +Kind, -Text, -Diags) is det.
%
%	Kind is `twod` (emit `display/2`) or `threed` (emit `display3d/2`). The
%	*plan* is the same either way, which is the point: the model describes
%	what is in the picture once and both renderings are computed from it.
%	Before this, "Animate in 3D" asked the model for coordinates in three
%	dimensions — the one part of the job §I.10.4e exists to take away from it.
scene_clauses(Plan, Kind, Text, Diags) :- scene_clauses(Plan, Kind, [], Text, Diags).

%!	scene_clauses(+Plan, +Kind, +Options, -Text, -Diags) is det.
%
%	Options are what the PROGRAM says about the plan's fluents, which the
%	model is never asked for because the program already knows
%	(AnimationPlan.md §6):
%
%	  * `derived(Keys)` — the `Name/Arity` of the plan's fluents that are
%	    *intensional*: defined by a rule rather than set by an event. They
%	    are drawn as outlines, because a reader who takes one for a stored
%	    fluent goes looking for the event that set it and there is none.
%	  * `order(Keys)` — the `Name/Arity` of the program's fluents in the
%	    order its rules mention them, so that two fluents that appear in one
%	    rule are drawn next to each other. Without it the row is in the
%	    order the model happened to list things in.
scene_clauses(Plan, Kind, Options, Text, Diags) :-
	scene_clauses(Plan, Kind, Options, Text, Diags, _).

%!	scene_clauses(+Plan, +Kind, +Options, -Text, -Diags, -Drawn) is det.
%
%	Drawn is `drawn(Keys, Containers, Things)`: what the generator
%	ACCEPTED — the `Name/Arity` of every shape that reached the page, and
%	how many containers and things are in it. Not what the plan asked for:
%	a plan whose every layer was skipped drew nothing, and the summary that
%	counted the plan said it had drawn four things (the review's R7). The
%	caller reports this, and measures its coverage on it.
scene_clauses(Plan, Kind, Options, Text, Diags, drawn(Keys, NG, NT)) :-
	( memberchk(instances(Inst), Options) -> true ; Inst = [] ),
	plan_groups(Plan, Groups00, D1),
	plan_layers(Plan, Inst, Layers00, Salvaged, D2),
	plan_gauges(Plan, Inst, Gauges00, D3),
	append(Gauges00, Salvaged, Gauges0),
	plan_stacks(Plan, Stacks00, D40),
	plan_spans(Plan, Spans0, D6),
	plan_grids(Plan, Inst, Grids0, D7),
	demote_stacks(Inst, Stacks00, Groups00, Layers00, Stacks0, Groups0, Layers0, D41),
	append(D40, D41, D4),
	promote_stacks(Inst, Groups0, Layers0, Stacks0, Groups, Layers0a, Stacks, D5),
	promote_grids(Inst, Layers0a, Layers0b, Grids0, Grids1, D8),
	grids_for(Kind, Grids1, Grids, D9),
	( memberchk(order(Order), Options) -> true ; Order = [] ),
	( memberchk(derived(Derived), Options) -> true ; Derived = [] ),
	by_rule_order(Order, gauge_pi, Gauges0, Gauges),
	by_rule_order(Order, layer_key, Layers0b, Layers),
	by_rule_order(Order, span_key, Spans0, Spans),
	append([D1, D2, D3, D4, D5, D6, D7, D8, D9], Diags0),
	%  A container that nothing can ever be put in is not a container: it is
	%  an empty box with a name in it, and the plan that asked for one asked
	%  for it by mistake (the review's R7 — "do not draw what was skipped").
	%  The gauges and the spans stay; only the dead geometry goes.
	(   Groups0 \== [], Layers == [], Stacks == []
	->  Groups1 = [],
	    Diags1 = [diag(warning, scene_no_layers_for_groups, none,
			   'the plan has containers but no layer putting anything in \c
them, so the containers are not drawn — a container is a place a fluent puts things \c
in, and no fluent puts anything in these', [])|Diags0]
	;   Groups1 = Groups, Diags1 = Diags0
	),
	drawn_report(Groups1, Layers, Gauges, Stacks, Spans, Grids, Keys, NG, NT),
	(   Groups1 == [], Gauges == [], Stacks == [], Spans == [], Grids == []
	->  Diags = [diag(error, scene_nothing, none,
			  'the plan names no containers, gauges, stacks, grids or spans, so \c
there is nothing to lay out — a fluent whose argument is a *place* is a container, one \c
whose argument is a *value* is a gauge, one that is simply true or false is a lamp (a \c
gauge with no value_var), one whose argument is another thing of the same kind is a \c
stack, one whose argument is a *position* on a map (X-Y) is a grid, and a composite \c
EVENT is a span', [])|Diags1],
	    Text = ""
	;   members_of(Layers, Members),
	    layout(Groups1, Members, Plan, Boxes, Slots, extent(W0, H0)),
	    stack_layout(Stacks, H0, Cols, extent(W1, H1a)),
	    grid_layout(Grids, H1a, PGrids, extent(WG, H1)),
	    W2 is max(W0, max(W1, WG)),
	    gauge_layout(Gauges, H1, GBoxes, H2),
	    span_layout(Spans, H2, SBoxes, H),
	    render(Kind, Plan, Layers, Stacks, Cols, Gauges, Spans, Derived,
		   Boxes, GBoxes, SBoxes, Slots, PGrids, extent(W2, H), Text),
	    free_variable_diags(Text, FDs),
	    append(FDs, Diags1, Diags)
	).

/*  What reached the page.
 *
 *  Every shape the readers ACCEPTED, by name, and the count of containers and
 *  things in the picture — which is not the count in the plan. This is what
 *  the caller says to the user and what it measures coverage against, so that
 *  a plan whose layers were all skipped cannot be reported as four things
 *  drawn (R7).
*/
drawn_report(Groups, Layers, Gauges, Stacks, Spans, Grids, Keys, NG, NT) :-
	findall(K,
		( ( member(layer(T, _, _, _, _), Layers)
		  ; member(grid(T, _, _, _, _, _, _), Grids)
		  ; member(gauge(T, _, _, _, _, _, _), Gauges)
		  ; member(stack(T, _, _, _, _), Stacks)
		  ; member(span(T, _, _, _, _), Spans) ),
		  functor(T, N, A), K = N/A ),
		Ks),
	sort(Ks, Keys),
	length(Groups, NG),
	members_of(Layers, LMs), length(LMs, NL),
	findall(N2, ( member(stack(_, _, _, Ms, _), Stacks), length(Ms, N2) ), SNs),
	sum_list(SNs, NS),
	findall(N3, ( member(gauge(_, _, _, GKs, _, _, _), Gauges),
		      length(GKs, N0), N3 is max(1, N0) ), GNs),
	sum_list(GNs, NGa),
	findall(N4, ( member(grid(_, _, _, GMs, _, _, _), Grids), length(GMs, N4) ), MNs),
	sum_list(MNs, NMa),
	NT is NL + NS + NGa + NMa.

/*  What was generated, read back.
 *
 *  A word that is capitalised is a VARIABLE, and a variable that occurs once in
 *  a clause is one nobody will ever bind: it is drawn as `_24584`. That is what
 *  a gauge labelled "Emergency" came out as before the label was quoted
 *  (render_gauge/1), and it is a whole class of mistake — anything of the
 *  model's that reaches a term position. So the clauses are read back before
 *  they are handed over, and a lone variable in one is reported as what it is.
 *  Every variable this file means to write is used at least twice (bound in the
 *  head and used in the properties, or bound by the body), so a singleton is
 *  never intended.
 */
free_variable_diags(Text, Diags) :-
	catch(setup_call_cleanup(open_string(Text, In),
				 singleton_loop(In, Diags),
				 close(In)),
	      _, Diags = []).

%	What a generated clause is about, for the message: the display subject.
clause_subject((H :- _), S) :- !, clause_subject(H, S).
clause_subject(D, S) :- compound(D), arg(1, D, S), !.
clause_subject(T, T).

singleton_loop(In, Diags) :-
	catch(read_term(In, T, [singletons(Ss)]), _, ( T = end_of_file, Ss = [] )),
	(   T == end_of_file
	->  Diags = []
	;   clause_subject(T, Subj),
	    findall(diag(warning, scene_free_variable, none, M, []),
		    ( member(Name = _, Ss),
		      \+ sub_atom(Name, 0, 1, _, '_'),
		      format(atom(M), 'the generated clause for ~q has a lone \c
variable `~w`, which draws as `_G123`: a word meant as text has reached a term \c
position', [Subj, Name]) ),
		    Ds),
	    append(Ds, Rest, Diags),
	    singleton_loop(In, Rest)
	).

		 /*******************************
		 *	   reading the plan	*
		 *******************************/

plan_groups(Plan, Groups, Diags) :-
	(   get_dict(groups, Plan, Gs), is_list(Gs)
	->  findall(g(Id, Label),
		    ( member(G, Gs), group_id_label(G, Id, Label) ), Groups),
	    Diags = []
	;   Groups = [], Diags = []
	).

group_id_label(G, Id, Label) :-
	is_dict(G), !,
	get_dict(id, G, Id0), text_atom(Id0, Id),
	( get_dict(label, G, L) -> text_atom(L, Label) ; Label = Id ).
group_id_label(G, Id, Id) :- text_atom(G, Id).

/*  No `layers` key is not an error any more. It was, when containers were the
    only way to put a fluent on the screen; a plan may now be all stacks, all
    gauges, or any mixture, and "the plan has no layers" was then a red
    diagnostic about a scene that had just been drawn correctly. The case it
    was really guarding — a plan that maps *nothing* — is checked once, at the
    top of scene_clauses/4, where all three shapes are in view. */
plan_layers(Plan, Inst, Layers, Salvaged, Diags) :-
	(   get_dict(layers, Plan, Ls), is_list(Ls)
	->  foldl(read_layer(Inst), Ls, l([], [], []), l(RevLayers, RevGs, RevDiags)),
	    reverse(RevLayers, Layers), reverse(RevGs, Salvaged),
	    reverse(RevDiags, Diags)
	;   Layers = [], Salvaged = [], Diags = []
	).

read_layer(Inst, L, l(Ls, Gs, Ds), l(Ls1, Gs1, Ds1)) :-
	(   is_dict(L),
	    get_dict(template, L, T0), text_atom(T0, TA),
	    %  Read *once*, keeping the variable names: reading a second time to
	    %  look a name up gives fresh variables, and then no argument is ever
	    %  the one the model meant.
	    catch(term_string(Tmpl, TA, [variable_names(Bs)]), _, fail),
	    compound(Tmpl),
	    get_dict(group_var, L, GV0), text_atom(GV0, GV),
	    get_dict(member_var, L, MV0), text_atom(MV0, MV),
	    arg_index(Tmpl, Bs, GV, GI),
	    arg_index(Tmpl, Bs, MV, MI)
	->  layer_members(L, Ms),
	    ( get_dict(shape, L, Sh0) -> text_atom(Sh0, Sh) ; Sh = raster ),
	    Ls1 = [layer(Tmpl, GI, MI, Ms, Sh)|Ls], Gs1 = Gs, Ds1 = Ds
	;   salvage_layer(L, Inst, Gauge, Note)
	->  Ls1 = Ls, Gs1 = [Gauge|Gs],
	    Ds1 = [diag(info, scene_layer_salvaged, none, Note, [])|Ds]
	;   Ls1 = Ls, Gs1 = Gs,
	    format(atom(M), 'a layer was skipped: it needs template, group_var and \c
member_var, and both variables must appear in the template (~q)', [L]),
	    Ds1 = [diag(warning, scene_bad_layer, none, M, [])|Ds]
	).

/*  A near miss, drawn anyway (R7c).
 *
 *  `promote_stacks/8` already forgives a plan that calls a support relation
 *  "containers"; this forgives the other common near miss, and for the same
 *  reason — the model was reaching for a shape that exists, and a warning the
 *  user never reads is not an answer. Two of them arrived from the same small
 *  model in one afternoon:
 *
 *    {"template": "loc(wolf, Where)", "member_var": "Object"}   a thing NAMED
 *    {"template": "fire(A)",          "member_var": "fire"}     a flag per room
 *
 *  Neither is a container and a member, because neither has two variables to
 *  be one with. Both are the shape R1 added: a template that names a
 *  particular thing is a GAUGE over the one variable it has left (`wolf:
 *  north`), and one that names none is a keyed LAMP over the values the run
 *  gave it (`on fire: kitchen`, `on fire: hall`). The run supplies the keys —
 *  the model is not asked to remember them.
*/
salvage_layer(L, Inst, gauge(Tmpl, VI, KI, Keys, Label, Colour, Fill), Note) :-
	is_dict(L),
	get_dict(template, L, T0), text_atom(T0, TA),
	catch(term_string(Tmpl, TA, [variable_names(_)]), _, fail),
	compound(Tmpl),
	term_variables(Tmpl, [V]),
	Tmpl =.. [Name|Args],
	nth1(VIdx, Args, A), A == V, !,
	length(Args, Arity), Consts is Arity - 1,
	( get_dict(color, L, C0) -> text_atom(C0, Colour) ; Colour = '#2f3542' ),
	( get_dict(pattern, L, P0) -> text_atom(P0, Fill) ; Fill = none ),
	(   Consts > 0
	->  %  it names a thing: what is left to show is that thing's value
	    VI = VIdx, KI = 0, Keys = [],
	    ( get_dict(label, L, L0) -> text_atom(L0, Label)
	    ; const_label(Args, V, Label) ),
	    format(atom(Note), 'a layer was drawn as a gauge instead: `~w` names one \c
thing rather than a thing and a place, so what is left to show is its value', [TA])
	;   run_keys(Inst, Tmpl, VIdx, Ks), Ks = [_, _|_]
	->  %  one flag per thing: a lamp each, over the values the run had
	    VI = 0, KI = VIdx, Keys = Ks,
	    ( get_dict(label, L, L0) -> text_atom(L0, Label) ; Label = Name ),
	    length(Ks, NK),
	    format(atom(Note), 'a layer was drawn as ~w lamps instead: `~w` is true or \c
false of one thing at a time, and the run had ~w of them', [NK, TA, NK])
	;   VI = VIdx, KI = 0, Keys = [],
	    ( get_dict(label, L, L0) -> text_atom(L0, Label) ; Label = Name ),
	    format(atom(Note), 'a layer was drawn as a gauge instead: `~w` has one \c
argument to show and no place to put anything in', [TA])
	).

%	A name made of the constants the template names — `loc(wolf, Where)` is
%	about the wolf, whatever the fluent is called.
const_label(Args, V, Label) :-
	findall(A, ( member(A, Args), A \== V, \+ var(A) ), Cs),
	(   Cs == []
	->  Label = ''
	;   findall(T, ( member(C, Cs), format(atom(T), '~w', [C]) ), Ts),
	    atomic_list_concat(Ts, ' ', Label)
	).

layer_members(L, Ms) :-
	(   get_dict(members, L, Xs), is_list(Xs)
	->  findall(m(Id, Icon, Colour, Label, Pattern, Model),
		    ( member(X, Xs),
		      member_spec(X, Id, Icon, Colour, Label, Pattern, Model) ), Ms)
	;   Ms = []
	).

member_spec(X, Id, Icon, Colour, Label, Pattern, Model) :-
	is_dict(X), !,
	get_dict(id, X, I0), text_atom(I0, Id),
	( get_dict(icon, X, C0) -> text_atom(C0, Icon) ; Icon = none ),
	( get_dict(color, X, K0) -> text_atom(K0, Colour) ; Colour = none ),
	( get_dict(label, X, L0) -> text_atom(L0, Label) ; Label = Id ),
	%  What its surface is like (ui/patterns) and what it is, in three
	%  dimensions (ui/models3d). `none` is "plain box": the renderers
	%  ignore a pattern or a model they do not have, so a plan that names
	%  neither draws exactly what it drew before.
	( get_dict(pattern, X, P0) -> text_atom(P0, Pattern) ; Pattern = none ),
	( get_dict(model, X, M0) -> text_atom(M0, Model) ; Model = none ).
member_spec(X, Id, none, none, Id, none, none) :- text_atom(X, Id).

%	Which argument of the template the named variable sits in. The model
%	writes `loc(Object, Where)` and says group_var is `Where`; this finds
%	that `Where` is argument 2, which is what the generated rule needs.
arg_index(Tmpl, Bindings, VarName, I) :-
	memberchk(VarName = V, Bindings),
	Tmpl =.. [_|Args],
	nth1(I, Args, A),
	A == V, !.

text_atom(X, A) :- atom(X), !, A = X.
text_atom(X, A) :- string(X), !, atom_string(A, X).
text_atom(X, A) :- term_to_atom(X, A).

/*  A **gauge** is the other common shape, and the one that made the first
    version of this file useless on half the corpus: a fluent whose argument is
    a *value* rather than a place — `heating(on)`, `balance(alice, 100)`,
    `temperature(14)`. There is nothing to contain and nothing to move; what the
    reader wants is a labelled box per fluent showing what it currently says.
    They are laid out in a row of their own above the containers. */
plan_gauges(Plan, Inst, Gauges, Diags) :-
	(   get_dict(gauges, Plan, Gs), is_list(Gs)
	->  foldl(read_gauge(Inst), Gs, l([], []), l(RevGs, RevDs)),
	    reverse(RevGs, Gauges), reverse(RevDs, Diags)
	;   Gauges = [], Diags = []
	).

read_gauge(Inst, G, l(Gs, Ds), l(Gs1, Ds1)) :-
	(   is_dict(G),
	    get_dict(template, G, T0), text_atom(T0, TA),
	    catch(term_string(Tmpl, TA, [variable_names(Bs)]), _, fail),
	    callable(Tmpl),
	    (   get_dict(value_var, G, VV0), VV0 \== "", VV0 \== null
	    ->  text_atom(VV0, VV), arg_index(Tmpl, Bs, VV, VI0)
	    ;   %  A fluent with no value to show — `alerted`, `stopped`,
		%  `in_station` — is a LAMP: the box is there while it holds
		%  and gone while it does not, which is the whole of what it
		%  has to say. Until this there was no shape for one, so the
		%  propositional fluents of a program could not be drawn at
		%  all: three of underground.lps's five, and the reader asked
		%  for exactly those three.
		VI0 = 0
	    ),
	    gauge_key(G, Tmpl, Bs, VI0, Inst, KI0, Keys0),
	    gauge_shape(Tmpl, Inst, VI0, KI0, Keys0, VI, KI, Keys)
	->  functor(Tmpl, Name, _),
	    ( get_dict(label, G, L0) -> text_atom(L0, Label) ; Label = Name ),
	    ( get_dict(color, G, C0) -> text_atom(C0, Colour) ; Colour = '#2f3542' ),
	    ( get_dict(pattern, G, P0) -> text_atom(P0, Fill) ; Fill = none ),
	    Gs1 = [gauge(Tmpl, VI, KI, Keys, Label, Colour, Fill)|Gs], Ds1 = Ds
	;   Gs1 = Gs,
	    format(atom(M), 'a gauge was skipped: it needs a template, and a \c
`value_var` naming one of that template\'s variables (leave `value_var` out for a \c
fluent that is simply true or false), and a `key_var` — if it has one — must name \c
another of them (~q)', [G]),
	    Ds1 = [diag(warning, scene_bad_gauge, none, M, [])|Ds]
	).

/*  A **keyed** gauge or lamp: one box per key, not one box per template
    (AnimationPlan.md §9 / the teacher's review R1).

    Almost every fluent worth drawing has a key — `balance(Who, Amount)`,
    `available(Fork)`, `fire(Room)`, `collateral(Account, Amount)` — and
    `display/2` draws only the FIRST solution for a subject. So a single box
    for `available(Fork)` showed one free fork of five, with the other four
    painted underneath it: a picture that is not thin but wrong. `key_var`
    names the argument that says *which one*, and `keys` lists the ones to
    give a place to — the assistant is told them, because the run knows them.

    A `key_var` with no keys is not an error: it draws the one box it can, as
    before, and says so. Nothing here changes an unkeyed gauge.
*/
/*  Which argument is the value and which the key — settled against the run,
    because a plan can say something the run contradicts and the run is right.

    Two corrections, both of them seen from real models on the corpus:

      * the SAME argument named as both (`available(Fork)` with `value_var`
	*and* `key_var` "Fork"). It cannot be both; what it is, is the key, and
	the fluent is then a lamp per fork. Left alone this generated
	`display(available(Key), [… label:Value])` — a lone variable, drawn as
	`_G123`.
      * an argument named as the VALUE that is really the key: `available(Fork)`
	with `value_var` "Fork". The tell is not in the plan but in the trace —
	the fluent holds of several of its instances AT ONCE, which a value
	never does (`temperature(14)` and `temperature(15)` are two cycles, not
	two boxes). So: several at a time is a lamp each, one at a time is a
	gauge, and the reader gets five forks rather than the first of five.
*/
gauge_shape(Tmpl, Inst, VI0, KI0, Keys0, VI, KI, Keys) :-
	(   KI0 > 0, KI0 =:= VI0
	->  VI = 0, KI = KI0,
	    ( Keys0 == [] -> run_keys(Inst, Tmpl, KI0, Keys) ; Keys = Keys0 )
	;   KI0 =:= 0, VI0 > 0, inst_together(Inst, Tmpl, Together), Together > 1,
	    run_keys(Inst, Tmpl, VI0, Ks), Ks = [_, _|_]
	->  VI = 0, KI = VI0, Keys = Ks
	;   VI = VI0, KI = KI0, Keys = Keys0
	).

%	How many instances of this fluent hold at the same time, at the busiest
%	cycle of the run. One is a value; more is a set of things.
inst_together(Inst, Tmpl, Together) :-
	functor(Tmpl, N, A),
	( memberchk(N/A-inst(_, T), Inst) -> Together = T ; Together = 0 ).

gauge_key(G, Tmpl, Bs, VI, Inst, KI, Keys) :-
	(   get_dict(key_var, G, KV0), KV0 \== "", KV0 \== null
	->  text_atom(KV0, KV), arg_index(Tmpl, Bs, KV, KI),
	    %  the plan's keys if it listed any, and otherwise the ones the run
	    %  actually had: the model has to say WHICH argument is the key, not
	    %  remember every value of it
	    ( gauge_keys(G, Ks), Ks \== [] -> Keys = Ks ; run_keys(Inst, Tmpl, KI, Keys) )
	;   infer_key(Inst, Tmpl, VI, KI, Keys)
	).

/*  The key, inferred.
 *
 *  A fluent that had more than one instance during the run is keyed whether or
 *  not the plan says so — `fire(kitchen)` and `fire(hall)` are two lamps, and
 *  one box for them is not a thin picture but a wrong one (R1). The run knows
 *  which argument tells them apart: it is the leftmost one, other than the
 *  value, that the instances differ in. A fluent with a single instance is not
 *  keyed, and neither is one the run says nothing about.
*/
infer_key(Inst, Tmpl, VI, KI, Keys) :-
	(   compound(Tmpl),
	    inst_together(Inst, Tmpl, Together), Together > 1,
	    functor(Tmpl, _, Arity),
	    between(1, Arity, P), P =\= VI,
	    run_keys(Inst, Tmpl, P, Ks), Ks = [_, _|_]
	->  KI = P, Keys = Ks
	;   KI = 0, Keys = []
	).

%	The distinct values the run gave one argument of this fluent, in the
%	order the run had them. Only the instances the template MATCHES count:
%	`loc(wolf, Where)` is about the wolf.
run_keys(Inst, Tmpl, I, Keys) :-
	integer(I), I > 0,
	functor(Tmpl, N, A),
	(   memberchk(N/A-Entry, Inst), inst_list(Entry, Fs)
	->  findall(K, ( member(F, Fs), \+ \+ Tmpl = F, arg(I, F, K), ground(K) ), Ks),
	    dedup(Ks, Keys)
	;   Keys = []
	).

%	The instances, however the caller recorded them: with the count of how
%	many hold at once, or as a bare list.
inst_list(inst(Fs, _), Fs) :- !.
inst_list(Fs, Fs) :- is_list(Fs).

dedup([], []).
dedup([X|Xs], [X|Ys]) :- exclude(==(X), Xs, Rest), dedup(Rest, Ys).

%	The key values, as the plan lists them: `keys` for preference, and
%	`members` because that is the word the plan uses everywhere else.
gauge_keys(G, Keys) :-
	(   get_dict(keys, G, Ks), is_list(Ks)
	->  findall(K, ( member(X, Ks), key_atom(X, K) ), Keys)
	;   get_dict(members, G, Ms), is_list(Ms)
	->  findall(K, ( member(X, Ms), key_atom(X, K) ), Keys)
	;   Keys = []
	).

key_atom(X, K) :- is_dict(X), !, get_dict(id, X, I), key_atom(I, K).
%	A number stays a number: `lps_cell(f, '5', …)` would never match the
%	fluent `f(5)`, and a key that does not match draws nothing at all.
key_atom(X, K) :- number(X), !, K = X.
key_atom(X, K) :- string(X), !,
	( catch(number_string(N, X), _, fail) -> K = N ; atom_string(K, X) ).
key_atom(X, K) :- text_atom(X, K).

/*  A **span** is the fifth shape, and the only one that is an EVENT rather
    than a fluent: a composite event — `makeLoc(goat, north) from 1 to 2` — is
    an *act*, a thing with a beginning and an end, and the one narrative shape
    the corpus can state that the picture could not draw.

    `{"template": "deal_with_goat(From, To)", "label": "crossing"}`, with an
    optional `member_var` naming the argument to put on the bar.

    The engine records a composite with its own interval, and
    `lps_display_scene/5` offers it to `display/2` as a subject (lps_explain.pl,
    composites_begun/3). So the bar's extent is not laid out here at all: it is
    computed, in the generated clause, from the act's own `Start` and `End`.
    What accumulates as the run goes on is a Gantt chart of it.
*/
plan_spans(Plan, Spans, Diags) :-
	(   get_dict(spans, Plan, Ss), is_list(Ss)
	->  foldl(read_span, Ss, l([], []), l(RevSs, RevDs)),
	    reverse(RevSs, Spans), reverse(RevDs, Diags)
	;   Spans = [], Diags = []
	).

read_span(Sp, l(Ss, Ds), l(Ss1, Ds1)) :-
	(   is_dict(Sp),
	    get_dict(template, Sp, T0), text_atom(T0, TA),
	    catch(term_string(Tmpl, TA, [variable_names(Bs)]), _, fail),
	    callable(Tmpl),
	    (   get_dict(member_var, Sp, MV0), MV0 \== "", MV0 \== null
	    ->  text_atom(MV0, MV), arg_index(Tmpl, Bs, MV, MI)
	    ;   MI = 0
	    )
	->  functor(Tmpl, Name, _),
	    ( get_dict(label, Sp, L0) -> text_atom(L0, Label) ; Label = Name ),
	    ( get_dict(color, Sp, C0) -> text_atom(C0, Colour) ; Colour = '#4c6ef5' ),
	    ( get_dict(pattern, Sp, P0) -> text_atom(P0, Fill) ; Fill = none ),
	    Ss1 = [span(Tmpl, MI, Label, Colour, Fill)|Ss], Ds1 = Ds
	;   Ss1 = Ss,
	    format(atom(M), 'a span was skipped: it needs a template naming a \c
composite event, and any `member_var` must be one of that template\'s variables (~q)',
		   [Sp]),
	    Ds1 = [diag(warning, scene_bad_span, none, M, [])|Ds]
	).

/*  The order the program's rules put its fluents in, applied to what the model
    listed (AnimationPlan.md §6). Two fluents that appear in one rule belong
    beside each other; one that no rule mentions belongs at the end. Stable:
    anything the order does not name keeps its place behind those it does.  */
by_rule_order([], _, Items, Items) :- !.
by_rule_order(Order, KeyPred, Items, Sorted) :-
	length(Order, N),
	findall(Rank-I,
		( nth0(J, Items, I),
		  Goal =.. [KeyPred, I, K],
		  ( call(Goal), nth0(P, Order, K) -> Rank is P * 1000 + J
		  ; Rank is N * 1000 + J ) ),
		Keyed),
	keysort(Keyed, Pairs),
	pairs_values(Pairs, Sorted).

gauge_pi(gauge(Tmpl, _, _, _, _, _, _), N/A) :- functor(Tmpl, N, A).
layer_key(layer(Tmpl, _, _, _, _), N/A) :- functor(Tmpl, N, A).
span_key(span(Tmpl, _, _, _, _), N/A) :- functor(Tmpl, N, A).

%	Is this shape's fluent one the program derives rather than stores?
is_derived(Derived, Tmpl) :-
	functor(Tmpl, N, A), memberchk(N/A, Derived).

members_of(Layers, Members) :-
	findall(Id, ( member(layer(_, _, _, Ms, _), Layers), member(m(Id, _, _, _, _, _), Ms) ), Ids0),
	sort(Ids0, Members).

		 /*******************************
		 *	     stacks		*
		 *******************************/

/*  A **stack** is the third shape: a fluent that says what a thing is standing
    on, where the thing it stands on is another thing of the same kind.

    `{"template":"on(Block, Support)", "member_var":"Block",
      "support_var":"Support", "members":[…]}`

    Only one stack is laid out. The generated helpers (`lps_pile_x/2`,
    `lps_pile_top/2`) are a recursion over one relation, and a second relation
    would need a second set under different names for no case anybody has: two
    independent support relations in one program. The rest are reported.
*/
plan_stacks(Plan, Stacks, Diags) :-
	(   get_dict(stacks, Plan, Ss), is_list(Ss)
	->  foldl(read_stack, Ss, l([], []), l(RevSs, RevDs)),
	    reverse(RevSs, Stacks), reverse(RevDs, Diags)
	;   Stacks = [], Diags = []
	).

only_one_stack([], [], D, D) :- !.
only_one_stack([S], [S], D, D) :- !.
only_one_stack([S|Rest], [S], D0, [Diag|D0]) :-
	length(Rest, N),
	format(atom(M), 'the plan has ~w more stack(s) than can be laid out; only the \c
first was used — two support relations in one picture would need two independent \c
towers, which this layer does not compute', [N]),
	Diag = diag(warning, scene_extra_stacks, none, M, []).

read_stack(S, l(Ss, Ds), l(Ss1, Ds1)) :-
	(   is_dict(S),
	    get_dict(template, S, T0), text_atom(T0, TA),
	    catch(term_string(Tmpl, TA, [variable_names(Bs)]), _, fail),
	    compound(Tmpl),
	    get_dict(member_var, S, MV0), text_atom(MV0, MV),
	    stack_support_var(S, SV),
	    arg_index(Tmpl, Bs, MV, MI),
	    arg_index(Tmpl, Bs, SV, SI),
	    MI \== SI
	->  layer_members(S, Ms),
	    stack_grounds(S, Gs),
	    Ss1 = [stack(Tmpl, MI, SI, Ms, Gs)|Ss], Ds1 = Ds
	;   Ss1 = Ss,
	    format(atom(M), 'a stack was skipped: it needs template, member_var and \c
support_var, and both variables must appear in the template in different argument \c
positions (~q)', [S]),
	    Ds1 = [diag(warning, scene_bad_stack, none, M, [])|Ds]
	).

%	`support_var` is the name; `group_var` is accepted too, because a model
%	that has just written three layers reaches for the word it used there.
stack_support_var(S, V) :- get_dict(support_var, S, V0), !, text_atom(V0, V).
stack_support_var(S, V) :- get_dict(group_var, S, V0), text_atom(V0, V).

%	What the piles stand on — `table`, `floor`, `ground`. Recorded for the
%	backdrop's label only: which thing is the floor is *derived* at run time
%	("something that is not itself standing on anything"), so a plan that
%	forgets to name it still draws the right picture.
stack_grounds(S, Gs) :-
	(   get_dict(ground, S, G0), is_list(G0)
	->  findall(A, ( member(X, G0), text_atom(X, A) ), Gs)
	;   get_dict(ground, S, G1), text_atom(G1, A)
	->  Gs = [A]
	;   Gs = []
	).

/*  A plan that called a support relation "containers", corrected.
 *
 *  This is the failure the shape was added for, and a better prompt does not
 *  make it go away: `on(Block, Support)` reads exactly like `loc(Object,
 *  Where)` unless you know that a block is also a place. The tell is in the
 *  plan itself — the containers *are* the things being contained — and it is
 *  cheap and safe to check: two names in common, and at least half the
 *  containers accounted for, before anything is promoted. The goat's two river
 *  banks share nothing with its four animals and are left alone.
 *
 *  Whatever is left over after the members are removed (`table`) is the floor,
 *  which is also the label the backdrop wants.
 */
promote_stacks(Inst, Groups, Layers, Stacks0, Groups1, Layers1, Stacks, Diags) :-
	findall(N/A, ( member(stack(T, _, _, _, _), Stacks0), functor(T, N, A) ), Already),
	promote_(Layers, Inst-Groups-Already, [], RevKept, [], RevFound, [], RevDiags),
	reverse(RevKept, Layers1),
	reverse(RevFound, Found),
	reverse(RevDiags, Diags0),
	%  An explicit stack outranks a promoted one: the model that wrote
	%  `stacks` said what it meant.
	append(Stacks0, Found, All),
	only_one_stack(All, Stacks, Diags0, Diags),
	%  A container that is now a block is not a container any more — and
	%  neither is the floor they all stand on, which the backdrop draws as a
	%  slab. Leaving either behind gave blocks world an empty box labelled
	%  `table` beside the tower, which is the picture this shape exists to
	%  stop drawing.
	stack_taken_ids(Stacks, Taken),
	exclude(group_promoted(Taken), Groups, Groups1).

group_promoted(Taken, g(Id, _)) :- memberchk(Id, Taken).

stack_taken_ids(Stacks, Ids) :-
	findall(Id, ( member(stack(_, _, _, Ms, Gs), Stacks),
		      ( member(m(Id, _, _, _, _, _), Ms) ; member(Id, Gs) ) ), Ids0),
	sort(Ids0, Ids).

promote_([], _, Kept, Kept, Fs, Fs, Ds, Ds).
promote_([L|Ls], Inst-Groups-Already, Kept0, Kept, Ss0, Ss, Ds0, Ds) :-
	L = layer(Tmpl, GI, MI, Ms, _Shape),
	functor(Tmpl, TN, TA),
	(   \+ memberchk(TN/TA, Already),
	    looks_like_stack(Groups, Ms, Shared, Floor),
	    %  The containers are shared with the things, but perhaps with the
	    %  things of ANOTHER layer: in `has(Who, Thing)` and `at(Who, Place)`
	    %  Mary holds the book and is in the library, and she is no more
	    %  standing on the library than the book is standing on her. The run
	    %  settles it, when there is one.
	    \+ run_denies_support(Inst, Tmpl, MI, GI)
	->  atomic_list_concat(Shared, ', ', SharedT),
	    ( Floor == [] -> FloorT = 'the floor'
	    ; atomic_list_concat(Floor, ', ', FloorT) ),
	    format(atom(M), 'the plan made containers of ~w, which are also things it \c
puts *in* containers — so ~w/~w is a support relation, not a place, and it has been laid \c
out as piles standing on ~w rather than as one box per thing',
		   [SharedT, TN, TA, FloorT]),
	    Ds1 = [diag(info, scene_promoted_stack, none, M, [])|Ds0],
	    Ss1 = [stack(Tmpl, MI, GI, Ms, Floor)|Ss0],
	    Kept1 = Kept0
	;   Ds1 = Ds0, Ss1 = Ss0, Kept1 = [L|Kept0]
	),
	promote_(Ls, Inst-Groups-Already, Kept1, Kept, Ss1, Ss, Ds1, Ds).

/*  What the run says about a support relation.

    A stack is a thing standing on a thing: somewhere in the run, what one
    instance has as its support is what another has as the thing standing —
    `on(a, b)` and `on(b, table)`. A relation whose supports never stand on
    anything is containment, whatever the plan called it: `has(crow, cheese)`
    puts the cheese in the crow's keeping, and drawn as a pile it drew the
    cheese on an invisible crow and never drew the crow or the fox at all.

    The run is evidence only when it has instances of the relation; a fluent
    that never held says nothing either way, and the plan is then taken at its
    word.
*/
run_denies_support(Inst, Tmpl, MI, SI) :-
	run_instances(Inst, Tmpl, Fs), Fs \== [],
	\+ ( member(F1, Fs), arg(SI, F1, S), ground(S),
	     member(F2, Fs), arg(MI, F2, M), M == S ).

run_instances(Inst, Tmpl, Fs) :-
	functor(Tmpl, N, A),
	(   memberchk(N/A-Entry, Inst), inst_list(Entry, Fs0)
	->  findall(F, ( member(F, Fs0), \+ \+ Tmpl = F ), Fs)
	;   Fs = []
	).

/*  A stack the run shows to be containment, drawn as containment.

    The other direction of promote_stacks/8, and the same mistake from the
    other side: a model told that "a thing on a thing gets a stack" reads
    `has(crow, cheese)` as the cheese on the crow. The supports the run had
    become containers (added to the plan's own, in the order the run met
    them), and the relation a layer putting its things in them.
*/
demote_stacks(Inst, Stacks0, Groups0, Layers0, Stacks, Groups, Layers, Diags) :-
	partition(stack_is_containment(Inst), Stacks0, Demoted, Stacks),
	foldl(demote_stack(Inst), Demoted, Groups0-Layers0-[], Groups-Layers1-RevDs),
	Layers = Layers1,
	reverse(RevDs, Diags).

stack_is_containment(Inst, stack(Tmpl, MI, SI, _, _)) :-
	run_denies_support(Inst, Tmpl, MI, SI).

demote_stack(Inst, stack(Tmpl, MI, SI, Ms0, _Grounds), G0-L0-D0, G1-L1-[Diag|D0]) :-
	run_keys(Inst, Tmpl, SI, Supports),
	findall(g(S, S), ( member(S, Supports), \+ memberchk(g(S, _), G0) ), New),
	append(G0, New, G1),
	%  The things are the ones the relation holds, not the containers
	%  a plan may have listed among them.
	exclude(member_is_support(Supports), Ms0, Ms1),
	(   Ms1 == []
	->  run_keys(Inst, Tmpl, MI, Things),
	    findall(m(T, none, none, T, none, none), member(T, Things), Ms)
	;   Ms = Ms1
	),
	append(L0, [layer(Tmpl, SI, MI, Ms, raster)], L1),
	functor(Tmpl, N, A),
	atomic_list_concat(Supports, ', ', ST),
	format(atom(M), 'the plan made a stack of ~w/~w, but in the run nothing it \c
holds is ever standing on anything — so it has been laid out as containers (~w) \c
with things in them, rather than as piles', [N, A, ST]),
	Diag = diag(info, scene_demoted_stack, none, M, []).

member_is_support(Supports, m(Id, _, _, _, _, _)) :- memberchk(Id, Supports).

looks_like_stack(Groups, Ms, Shared, Floor) :-
	findall(Id, member(g(Id, _), Groups), GIds0), sort(GIds0, GIds),
	GIds \== [],
	findall(Id, member(m(Id, _, _, _, _, _), Ms), MIds0), sort(MIds0, MIds),
	intersection(GIds, MIds, Shared),
	length(Shared, NS), NS >= 2,
	length(GIds, NG),
	NS * 2 >= NG,
	subtract(GIds, MIds, Floor).

		 /*******************************
		 *	     the layout		*
		 *******************************/

/*  Box flow, in one pass.
 *
 *  Every group gets the *same* grid, sized for the whole cast, because a thing
 *  moves between groups and its slot must not move with it: the wolf is in
 *  column 1 whichever bank it is on. That is the property that makes an
 *  animation readable, and it is also what a per-group packing would destroy.
 */
layout([], _, _, [], [], extent(0, 0)) :- !.
layout(Groups, Members, Plan, Boxes, Slots, extent(W, H)) :-
	length(Members, N),
	max_cols(MC),
	Cols is max(1, min(MC, N)),
	Rows is max(1, ceiling(N / Cols)),
	cell(C), gap(G), pad(P), title_h(TH), group_gap(GG),
	InnerW is Cols * C + (Cols - 1) * G,
	InnerH is Rows * C + (Rows - 1) * G,
	BoxW is InnerW + 2 * P,
	BoxH is InnerH + 2 * P + TH,
	( get_dict(orientation, Plan, "column") -> Dir = column ; Dir = row ),
	length(Groups, NG),
	%  Containers flow along the model's axis and wrap, like text: eight of them
	%  in one column is a scene six times taller than it is wide, and everything
	%  in it is then drawn at a sixth of the size the pane could give it.
	per_line(Dir, NG, BoxW, BoxH, GG, PL),
	Lines is ceiling(NG / PL),
	( Dir == row -> GCols = PL, GRows = Lines ; GCols = Lines, GRows = PL ),
	findall(box(Id, Label, X0, Y0, BoxW, BoxH),
		( nth0(K, Groups, g(Id, Label)),
		  ( Dir == row
		  ->  GCol is K mod PL, GRow is K // PL
		  ;   GCol is K // PL, GRow is K mod PL ),
		  X0 is GCol * (BoxW + GG),
		  %  y grows upward, so the first line is the top one.
		  Y0 is (GRows - 1 - GRow) * (BoxH + GG)
		),
		Boxes),
	W is GCols * BoxW + (GCols - 1) * GG,
	H is GRows * BoxH + (GRows - 1) * GG,
	findall(slot(GId, MId, SX, SY),
		( member(box(GId, _, BX, BY, _, _), Boxes),
		  nth0(J, Members, MId),
		  Col is J mod Cols, Row is J // Cols,
		  SX is BX + P + Col * (C + G) + C / 2,
		  %  y grows upward, so row 0 is the *top* row of the grid.
		  SY is BY + P + (Rows - 1 - Row) * (C + G) + C / 2
		),
		Slots).

/*  How many containers per line. Below `wrap_from` the model's own axis is
    honoured exactly — two river banks side by side are side by side because
    that is what the program is about, and a squarer arrangement of two boxes
    would be a worse picture, not a better one. Above it, the count is chosen so
    that the finished scene is as close to `target_ratio` as it can get, which
    is the only thing that decides how large anything is drawn.
*/
per_line(_, NG, _, _, _, NG) :-
	wrap_from(Min), NG < Min, !.
per_line(Dir, NG, BoxW, BoxH, GG, PL) :-
	findall(Score-L,
		( between(1, NG, L), line_score(Dir, NG, BoxW, BoxH, GG, L, Score) ),
		Scored),
	sort(Scored, [_-PL|_]).

line_score(Dir, NG, BoxW, BoxH, GG, L, Score) :-
	Lines is ceiling(NG / L),
	( Dir == row -> Cols = L, Rows = Lines ; Cols = Lines, Rows = L ),
	W is Cols * BoxW + (Cols - 1) * GG,
	H is Rows * BoxH + (Rows - 1) * GG,
	target_ratio(T),
	Score is abs(log(W / H / T)).

/*  A pile's columns, and the band they stand in.
 *
 *  All that is *static* about a stack is which column each pile gets — one per
 *  thing, because in the worst case every thing is standing on the floor in a
 *  pile of its own. Everything else (which pile a thing is in, how high up it
 *  is) is computed at draw time from the state, so there is no slot table.
 *
 *  The band is as tall as the tallest tower could ever be — every thing on top
 *  of every other — which is what keeps the scale steady while the tower is
 *  taken apart: `fit()` in the renderer scales to the scene's extent, and a
 *  backdrop that shrank with the tower would make the blocks change size every
 *  time one moved.
 */
stack_layout([], H, [], extent(0, H)) :- !.
stack_layout([stack(_, _, _, Ms, _)|_], H0, Cols, extent(W, H)) :-
	length(Ms, N0), N is max(1, N0),
	cell(C), pitch_x(PX), pitch_y(PY), floor_h(FH),
	( H0 =:= 0 -> Base is FH ; Base is H0 + 28 + FH ),
	findall(col(Id, X, Base),
		( nth0(K, Ms, m(Id, _, _, _, _, _)), X is K * PX + C / 2 ),
		Cols),
	W is N * PX - (PX - C),
	H is Base + N * PY.

/*  One row of boxes, above whatever the containers occupy — and a KEYED gauge
    or lamp takes one box per key rather than one box for the lot (the review's
    R1). The row is laid out left to right in the order the gauges were given
    (which is the order the program's rules mention them, §6), each gauge's
    keys kept together.

    Every box is a *cell*, and every cell is also a SOCKET: the backdrop draws
    its outline and its caption whether or not the fluent holds, so that "off"
    looks like off rather than like a picture that failed to draw (R2).
*/
gauge_layout([], H, [], H) :- !.
gauge_layout(Gauges, H0, Placed, H) :-
	gauge_cell_w(GW), gauge_cell_h(GH), gauge_cell_gap(GG),
	( H0 =:= 0 -> Y = 0 ; Y is H0 + 24 ),
	place_gauges(Gauges, 0, Y, GW, GH, GG, Placed),
	H is Y + GH.

place_gauges([], _, _, _, _, _, []).
place_gauges([G|Gs], X0, Y, GW, GH, GG, [placed(G, Cells)|Rest]) :-
	G = gauge(_, _, KI, Keys, _, _, _),
	(   KI > 0, Keys = [_|_]
	->  findall(cell(Key, X, Y, GW, GH),
		    ( nth0(I, Keys, Key), X is X0 + I * (GW + GG) ),
		    Cells),
	    length(Keys, N)
	;   Cells = [cell(none, X0, Y, GW, GH)], N = 1
	),
	X1 is X0 + N * (GW + GG),
	place_gauges(Gs, X1, Y, GW, GH, GG, Rest).

%	How wide the row of cells is, end to end.
gauge_row_width(Placed, W) :-
	findall(X1, ( member(placed(_, Cells), Placed),
		      member(cell(_, X, _, CW, _), Cells), X1 is X + CW ),
		Xs),
	( Xs == [] -> W = 0 ; max_list(Xs, W) ).

/*  The picture's caption — unless it is the prompt's own example, copied
    verbatim. A small model handed back `"title": "a short caption"` and the
    scene was captioned "a short caption"; a placeholder is not worse than no
    title, it is worse, because it says the system was not paying attention.
*/
plan_title(Plan, Title) :-
	( get_dict(title, Plan, T0) -> text_atom(T0, T) ; T = '' ),
	downcase_atom(T, D),
	( placeholder_title(D) -> Title = '' ; Title = T ).

placeholder_title('a short caption').
placeholder_title('a short caption for the picture').
placeholder_title(title).
placeholder_title('a title').
placeholder_title('the title').

%	A cell's size, and the gap between two of them.
gauge_cell_w(150).
gauge_cell_h(40).
gauge_cell_gap(12).

/*  One lane per span, above the gauges. Only the lane's *height* is laid out
    here: where a bar starts and stops along it is the act's own business, and
    the generated clause computes it from `Start` and `End`.  */
span_layout([], H, [], H) :- !.
span_layout(Spans, H0, Bars, H) :-
	span_lane_h(LH), span_lane_gap(LG),
	( H0 =:= 0 -> Y0 = 0 ; Y0 is H0 + 24 ),
	findall(sbar(Tmpl, MI, Label, Colour, Fill, Y),
		( nth0(K, Spans, span(Tmpl, MI, Label, Colour, Fill)),
		  Y is Y0 + K * (LH + LG) ),
		Bars),
	length(Spans, N),
	H is Y0 + N * (LH + LG) - LG.

%	A lane's height, the gap between lanes, how many pixels a cycle is
%	worth along one, and how wide the captions' gutter to the left is.
span_lane_h(14).
span_lane_gap(8).
span_pitch(24).
span_gutter(118).

		 /*******************************
		 *	    rendering		*
		 *******************************/

/*  Two renderings of one plan.
 *
 *  `twod` emits `display/2`, `threed` emits `display3d/2`. They share the
 *  layout entirely: the container grid computed above is a *floor plan*, so in
 *  three dimensions the same (x, y) becomes (x, z) on the ground and the things
 *  stand up out of it. A stack needs no such translation — a tower is a tower.
 */
render(twod, Plan, Layers, Stacks, Cols, Gauges, Spans, Derived, Boxes, GBoxes, SBoxes, Slots, PGrids, Extent, Text) :- !,
	render_2d(Plan, Layers, Stacks, Cols, Gauges, Spans, Derived, Boxes, GBoxes, SBoxes, Slots, PGrids, Extent, Text).
render(threed, Plan, Layers, Stacks, Cols, Gauges, Spans, Derived, Boxes, GBoxes, SBoxes, Slots, _PGrids, Extent, Text) :-
	render_3d(Plan, Layers, Stacks, Cols, Gauges, Spans, Derived, Boxes, GBoxes, SBoxes, Slots, Extent, Text).

		 /*******************************
		 *	   two dimensions	*
		 *******************************/

render_2d(Plan, Layers, Stacks, Cols, _Gauges, _Spans, Derived, Boxes, GBoxes, SBoxes, Slots, PGrids, extent(W0, H), Text) :-
	gauge_row_width(GBoxes, GRW),
	( GRW =:= 0 -> W = W0 ; W is max(W0, GRW) ),
	plan_title(Plan, Title),
	cell(C),
	with_output_to(string(Text),
	    ( header_comment(Slots, Stacks),
	      forall(member(layer(Tmpl, GI, MI, Ms, Shape), Layers),
		     render_layer(Tmpl, GI, MI, Ms, Shape, C, Derived)),
	      forall(member(PG, PGrids), render_grid(PG, Derived)),
	      forall(member(S, Stacks), render_stack_2d(S, C)),
	      forall(member(GB, GBoxes), render_gauge(GB, Derived)),
	      forall(member(SB, SBoxes), render_span(SB)),
	      nl,
	      render_backdrop(Title, Boxes, GBoxes, SBoxes, Stacks, Cols, PGrids, W, H),
	      nl,
	      render_cells(GBoxes),
	      nl,
	      (   Slots == []
	      ->  true
	      ;   format('%  Where each thing sits in each container. One row per pair, so a~n'),
		  format('%  thing keeps its column wherever it is.~n'),
		  forall(member(slot(G, M, X, Y), Slots),
			 format('lps_slot(~q, ~q, ~2f, ~2f).~n', [G, M, X, Y])),
		  nl
	      ),
	      render_columns(Cols),
	      forall(member(PG, PGrids), render_grid_helper(PG)),
	      findall(layer(T, 0, 0, GMs, S), member(pgrid(grid(T, _, _, GMs, _, S, _), _, _, _, _), PGrids), GLs),
	      append(Layers, GLs, LayersAll),
	      all_members(LayersAll, Stacks, AllMs),
	      render_looks(AllMs)
	    )).

header_comment(Slots, Stacks) :-
	format('%  Scene generated by the LPS2 assistant: the plan was the model\'s,~n'),
	format('%  the geometry is this file\'s (src/edges/lps_scene.pl). The model~n'),
	format('%  never writes a coordinate.~n'),
	( Slots == [] -> true
	; format('%  A thing\'s position in a container comes from lps_slot/4 below, so~n'),
	  format('%  nothing can overlap — move a slot and everything that ever sits in~n'),
	  format('%  it moves with it.~n') ),
	( Stacks == [] -> true
	; format('%  A thing in a pile is placed by walking the state: lps_pile_top/2~n'),
	  format('%  and lps_pile_x/2 below read `state/1` at the cycle being drawn, so~n'),
	  format('%  a tower is built and taken apart as the program builds and takes it~n'),
	  format('%  apart.~n') ),
	nl.

all_members(Layers, Stacks, Ms) :-
	findall(M, ( ( member(layer(_, _, _, L, _), Layers)
		     ; member(stack(_, _, _, L, _), Stacks) ),
		     member(M, L) ), Ms0),
	dedup_members(Ms0, Ms).

%	One `lps_look/3` fact per thing, even when a thing is named by two
%	layers: a duplicate clause is a second solution for the same key and the
%	scene would draw whichever came first, silently.
dedup_members(Ms0, Ms) :- dedup_members_(Ms0, [], Ms).

dedup_members_([], _, []).
dedup_members_([m(Id, I, C, L, P, M)|Xs], Seen, Out) :-
	(   memberchk(Id, Seen)
	->  Out = Rest, Seen1 = Seen
	;   Out = [m(Id, I, C, L, P, M)|Rest], Seen1 = [Id|Seen]
	),
	dedup_members_(Xs, Seen1, Rest).

render_layer(Tmpl, GI, MI, _Ms, Shape, C, Derived) :-
	arg_text(Tmpl, [GI-'Where', MI-'What'], Name, ArgText),
	Half is C / 2,
	%  A DERIVED fluent is drawn as an outline: no rule sets it, so a reader
	%  who takes it for a stored one goes looking for an event that is not
	%  there (AnimationPlan.md §6).
	( is_derived(Derived, Tmpl) -> Paint = 'strokeColor' ; Paint = 'fillColor' ),
	(   Shape == raster
	->  format('display(~w(~w), [type:raster, icon:Icon, position:[X, Y], scale:0.5]) :-~n\c
\tlps_slot(Where, What, CX, CY), X is CX - ~2f, Y is CY - ~2f,~n\c
\tlps_look(What, Icon, _).~n~n', [Name, ArgText, Half, Half])
	;   Shape == box
	->  format('display(~w(~w), [type:rectangle, from:[X0, Y0], to:[X1, Y1],~n\c
\t\t     ~w:Colour, pattern:Fill, label:What]) :-~n\c
\tlps_slot(Where, What, CX, CY),~n\c
\tX0 is CX - ~2f, Y0 is CY - ~2f, X1 is CX + ~2f, Y1 is CY + ~2f,~n\c
\tlps_look(What, _, Colour), lps_style(What, Fill, _).~n~n',
		   [Name, ArgText, Paint, Half, Half, Half, Half])
	;   format('display(~w(~w), [type:circle, center:[CX, CY], radius:~2f,~n\c
\t\t     ~w:Colour, pattern:Fill, label:What]) :-~n\c
\tlps_slot(Where, What, CX, CY),~n\c
\tlps_look(What, _, Colour), lps_style(What, Fill, _).~n~n',
		   [Name, ArgText, Half, Paint])
	).

/*  A pile, in two dimensions.
 *
 *  One rule and two recursions, and between them they are the whole difference
 *  from a container: a thing is drawn *on top of* what it is standing on, at
 *  the height that follows from the state, in the column its pile occupies.
 */
render_stack_2d(stack(Tmpl, MI, SI, _Ms, Grounds), C) :-
	arg_text(Tmpl, [SI-'Where', MI-'What'], Name, ArgText),
	Half is C / 2,
	pitch_y(PY),
	stack_goal(Tmpl, MI, SI, 'T', 'S', OnTS),
	stack_goal(Tmpl, MI, SI, 'S', '_', OnS),
	format('display(~w(~w), [type:rectangle, from:[X0, Y0], to:[X1, Y1],~n\c
\t\t     fillColor:Colour, label:What]) :-~n\c
\tlps_pile_x(What, CX), lps_pile_top(Where, BY),~n\c
\tlps_look(What, _, Colour),~n\c
\tX0 is CX - ~2f, X1 is CX + ~2f, Y0 is BY, Y1 is BY + ~2f.~n~n',
	       [Name, ArgText, Half, Half, C]),
	render_stack_helpers('', OnTS, OnS, PY, Grounds).

/*  The recursions, written once and shared by both renderings — the constants
    are the only difference, and they are arguments.

    The depth guard is not decoration: `on(a,b), on(b,a)` is a state a program
    can reach while a plan is half applied, and without it the scene layer hangs
    the pane rather than drawing a wrong picture. */
render_stack_helpers(Sfx, OnTS, OnS, Pitch, Grounds) :-
	(   Grounds == []
	->  true
	;   atomic_list_concat(Grounds, ', ', GT),
	    format('%  The floor is ~w.~n', [GT])
	),
	format('%  How high the top of a support is: the floor is 0, and anything~n'),
	format('%  standing on something else is one pitch above whatever *it* stands on.~n'),
	format('lps_pile_top~w(T, Y) :- lps_pile_top~w_(T, 0, Y).~n', [Sfx, Sfx]),
	format('lps_pile_top~w_(_, D, 0.0) :- D > 64, !.~n', [Sfx]),
	format('lps_pile_top~w_(T, D, Y) :- ~w, !,~n\c
\tD1 is D + 1, lps_pile_top~w_(S, D1, Y0), Y is Y0 + ~2f.~n', [Sfx, OnTS, Sfx, Pitch]),
	format('lps_pile_top~w_(_, _, 0.0).~n~n', [Sfx]),
	format('%  Which column a pile stands in. A pile is named by its bottom-most~n'),
	format('%  member — the one standing on something that is not itself standing on~n'),
	format('%  anything — so a tower keeps its column while it is taken apart and~n'),
	format('%  rebuilt somewhere else.~n'),
	format('lps_pile_x~w(T, X) :- lps_pile_x~w_(T, 0, X).~n', [Sfx, Sfx]),
	format('lps_pile_x~w_(_, D, 0.0) :- D > 64, !.~n', [Sfx]),
	format('lps_pile_x~w_(T, _, X) :- ~w, \\+ ~w, !, lps_column~w(T, X).~n', [Sfx, OnTS, OnS, Sfx]),
	format('lps_pile_x~w_(T, D, X) :- ~w, !, D1 is D + 1, lps_pile_x~w_(S, D1, X).~n', [Sfx, OnTS, Sfx]),
	format('lps_pile_x~w_(T, _, X) :- lps_column~w(T, X), !.~n', [Sfx, Sfx]),
	format('lps_pile_x~w_(_, _, 0.0).~n~n', [Sfx]).

/*  `state(on(T, S))` — built from the template, because the relation is the
    program's and only its *shape* is known here. `state/1` is the engine's own
    view of the current state; `holds/2` is internal vocabulary with no clauses
    and calling it from a program's Prolog silently fails, which puts every
    block on the floor (the note in examples/start/blocks3d.lps is about exactly that
    afternoon). */
stack_goal(Tmpl, MI, SI, MVar, SVar, Goal) :-
	arg_text(Tmpl, [MI-MVar, SI-SVar], Name, ArgText),
	format(atom(Goal), 'state(~w(~w))', [Name, ArgText]).

/*  The template's arguments, with the named positions replaced. What is left
    is an anonymous variable — except where the plan wrote a CONSTANT, which is
    kept: `loc(wolf, Where)` is about the wolf, and a head of `loc(_, Value)`
    would draw the first thing anywhere rather than where the wolf is.
*/
arg_text(Tmpl, Pairs, Name, ArgText) :-
	Tmpl =.. [Name|Args],
	length(Args, Arity),
	numlist(1, Arity, Is),
	findall(V, ( member(I, Is), nth1(I, Args, A),
		     ( memberchk(I-V0, Pairs) -> V = V0
		     ; var(A) -> V = '_'
		     ; format(atom(V), '~q', [A]) ) ), Vs),
	atomic_list_concat(Vs, ', ', ArgText).

render_columns([]) :- !.
render_columns(Cols) :-
	format('%  One column per thing: in the worst case every thing is standing on~n'),
	format('%  the floor in a pile of its own.~n'),
	forall(member(col(Id, X, _), Cols), format('lps_column(~q, ~2f).~n', [Id, X])),
	nl.

/*  A gauge is one rule: whatever value the fluent has, in its own box.
 *
 *  The label is written QUOTED, and that is not cosmetic. It is a word the
 *  model chose, so it is as likely to arrive capitalised as not — "Emergency",
 *  "Penalty" — and a capitalised word in a term is a *variable*: the box came
 *  out labelled `_24584:fire`, which is what a free variable prints as. `~q`
 *  makes it the atom it was meant to be, whatever its first letter.
 */
render_gauge(placed(gauge(Tmpl, VI, KI, _, Label, Colour, Fill), Cells), Derived) :-
	pattern_prop(Fill, Pat),
	( is_derived(Derived, Tmpl) -> Paint = 'strokeColor' ; Paint = 'fillColor' ),
	functor(Tmpl, Name0, _),
	(   KI > 0, Cells = [cell(K0, _, _, _, _)|_], K0 \== none
	->  %  KEYED: one box per key, placed by the generated cell table, so
	    %  five free forks are five boxes rather than one box showing the
	    %  first of them (the review's R1). The box says the VALUE (or, for
	    %  a lamp, the label); which key it is, is the caption above its
	    %  socket.
	    (   VI =:= 0
	    ->  arg_text(Tmpl, [KI-'Key'], Name, ArgText),
		format('display(~w(~w), [type:rectangle, from:[X0, Y0], to:[X1, Y1],~n\c
\t\t     ~w:~q~w, label:~q]) :-~n\c
\tlps_cell(~q, Key, X0, Y0, X1, Y1).~n~n',
		       [Name, ArgText, Paint, Colour, Pat, Label, Name0])
	    ;   arg_text(Tmpl, [KI-'Key', VI-'Value'], Name, ArgText),
		format('display(~w(~w), [type:rectangle, from:[X0, Y0], to:[X1, Y1],~n\c
\t\t     ~w:~q~w, label:Value]) :-~n\c
\tlps_cell(~q, Key, X0, Y0, X1, Y1).~n~n',
		       [Name, ArgText, Paint, Colour, Pat, Name0])
	    )
	;   Cells = [cell(_, X, Y, W, H)|_],
	    X1 is X + W, Y1 is Y + H,
	    (   VI =:= 0
	    ->  %  a lamp: no value, so the box says its own name and its being
		%  there at all is the fact (the socket below it stays, so the
		%  reader sees the empty place while it does not hold)
		lamp_head(Tmpl, Head),
		format('display(~w, [type:rectangle, from:[~2f, ~2f], to:[~2f, ~2f],~n\c
\t\t     ~w:~q~w, label:~q]).~n~n',
		       [Head, X, Y, X1, Y1, Paint, Colour, Pat, Label])
	    ;   arg_text(Tmpl, [VI-'Value'], Name, ArgText),
		format('display(~w(~w), [type:rectangle, from:[~2f, ~2f], to:[~2f, ~2f],~n\c
\t\t     ~w:~q~w, label:(~q:Value)]).~n~n',
		       [Name, ArgText, X, Y, X1, Y1, Paint, Colour, Pat, Label])
	    )
	).

%	Where each keyed box sits. One row per (fluent, key), so the socket in
%	the backdrop and the box that fills it cannot disagree about a place.
render_cells(Placed) :-
	findall(c(N, K, X, Y, X1, Y1),
		( member(placed(gauge(Tmpl, _, KI, _, _, _, _), Cells), Placed),
		  KI > 0, functor(Tmpl, N, _),
		  member(cell(K, X, Y, W, H), Cells), K \== none,
		  X1 is X + W, Y1 is Y + H ),
		Cs),
	(   Cs == []
	->  true
	;   format('%  Where each keyed box sits: one row per fluent and key, so a~n'),
	    format('%  fluent with five keys has five places rather than one.~n'),
	    forall(member(c(N, K, X, Y, X1, Y1), Cs),
		   format('lps_cell(~q, ~q, ~2f, ~2f, ~2f, ~2f).~n', [N, K, X, Y, X1, Y1])),
	    nl
	).

/*  A span is one rule, and its geometry is the act's OWN interval: the
    composite carries `Start` and `End`, so the bar is computed from them
    rather than laid out here. An act that lasted one cycle still gets a
    visible stub (`min_w`), and an act that is over stays on the chart —
    `composites_begun/3` keeps offering it, which is what makes the lane read
    as a history rather than as a flash.  */
render_span(sbar(Tmpl, MI, Label, Colour, Fill, Y)) :-
	span_lane_h(LH), span_pitch(Pitch),
	pattern_prop(Fill, Pat),
	Y1 is Y + LH,
	span_head(Tmpl, MI, Label, Head, LabelText),
	%  The two clauses that write NOTHING on the bar must not name the thing
	%  either: a variable in the head that no property uses is a singleton,
	%  and the free-variable check is right to call it out.
	span_head(Tmpl, 0, Label, Anon, _),
	label_width(Label, MI, Wmin),
	TY is Y + 3, TY1 is Y1 - 3,
	%  An act that TAKES TIME is a bar from its own start to its own end.
	format('%  A bar for an act that lasts: from its own start to its own end.~n'),
	format('display(happens(~w, S, E), [type:rectangle, from:[X0, ~2f], to:[X1, ~2f],~n\c
\t\t     fillColor:~q~w, label:~w]) :-~n\c
\tE > S, X0 is S * ~2f, X1 is E * ~2f, X1 - X0 >= ~2f.~n~n',
	       [Head, Y, Y1, Colour, Pat, LabelText, Pitch, Pitch, Wmin]),
	%  …the same bar when the label would not fit in it. A word printed
	%  over a sliver is not a label, it is the next bar's label as well:
	%  twenty of them made the goat's lane read `m m m m moving:wolfge`
	%  (the review's R8).
	format('%  …and the same bar, unlabelled, when the label would be wider than it.~n'),
	format('display(happens(~w, S, E), [type:rectangle, from:[X0, ~2f], to:[X1, ~2f],~n\c
\t\t     fillColor:~q~w]) :-~n\c
\tE > S, X0 is S * ~2f, X1 is E * ~2f, X1 - X0 < ~2f.~n~n',
	       [Anon, Y, Y1, Colour, Pat, Pitch, Pitch, Wmin]),
	%  An act whose start is its end did not take time: it is a point on
	%  the lane, and drawing it as a bar says something false about it.
	format('%  A tick for an instant: an act whose start is its end is a point,~n'),
	format('%  not something that lasted. The timeline lists every one of them.~n'),
	format('display(happens(~w, S, E), [type:rectangle, from:[X0, ~2f], to:[X1, ~2f],~n\c
\t\t     fillColor:~q]) :-~n\c
\tE =:= S, X0 is S * ~2f - 1.5, X1 is X0 + 3.0.~n~n',
	       [Anon, TY, TY1, Colour, Pitch]).

%	The head of a span's rule, and what its bar is called.
span_head(Tmpl, MI, Label, Head, LabelText) :-
	( MI =:= 0 -> Lab = Label, Pairs = [] ; Lab = (Label:'What'), Pairs = [MI-'What'] ),
	arg_text(Tmpl, Pairs, Name, ArgText),
	( ArgText == '' -> format(atom(Head), '~w', [Name])
	; format(atom(Head), '~w(~w)', [Name, ArgText]) ),
	(   Lab = (L:V)
	->  format(atom(LabelText), '(~q:~w)', [L, V])
	;   format(atom(LabelText), '~q', [Lab])
	).

/*  How wide the label will be, near enough. There is no font here to measure
    with, so this is the label's own length plus room for the value the bar
    carries, at the width of a character of the renderer's 11px face. Being a
    little generous is the safe direction: the cost of a missing label is a bar
    the timeline explains, and the cost of one that does not fit is every
    label on the lane unreadable.
*/
label_width(Label, MI, W) :-
	atom_length(Label, N0),
	( MI =:= 0 -> N = N0 ; N is N0 + 9 ),
	W is N * 6.5 + 8.

%	`pattern:<name>` as a property, or nothing at all when the plan named
%	none — a renderer ignores a fill it does not have, but an empty property
%	is noise in a file somebody reads.
pattern_prop(none, '') :- !.
pattern_prop(Fill, P) :- format(atom(P), ', pattern:~q', [Fill]).

%	The head of a lamp's rule: the fluent itself, its arguments (if it has
%	any) left as anonymous variables — it is drawn whenever it holds, of
%	whatever.
lamp_head(Tmpl, Head) :-
	%  `alerted` is an atom and has no argument list at all — not even an
	%  empty one, which `alerted()` would be and which does not read.
	(   atom(Tmpl)
	->  Head = Tmpl
	;   arg_text(Tmpl, [], Name, ArgText),
	    format(atom(Head), '~w(~w)', [Name, ArgText])
	).

/*  The backdrop: the frame, the container names, the gauges' names, the title.
 *
 *  Where a piece of text GOES needs one fact about the renderer: a text item's
 *  point is its top-left and the text is drawn DOWNWARD from it (scene2d.js
 *  counter-flips the glyphs so they read the right way up in a y-grows-up
 *  scene). So a caption above something must sit its own height *plus* the gap
 *  above it, not the gap alone — the gauge names were four units above their
 *  boxes and therefore printed across the top of them, which is what
 *  "Emergency" hiding under its own gauge was.
 */
render_backdrop(Title, Boxes, GBoxes, SBoxes, Stacks, Cols, PGrids, W, H) :-
	gauge_label_h(GLH), gauge_label_gap(GLG),
	( GBoxes == [] -> Band = 0 ; Band is GLH + GLG ),
	( SBoxes == [] -> Left = -14 ; span_gutter(G), Left is -G - 14 ),
	TitleY is H + Band + 26,
	TopY is TitleY + 20,
	format('display(timeless, [~n'),
	format('\t[type:rectangle, from:[~2f, -26], to:[~2f, ~2f], strokeColor:\'#2a2f3a\']', [Left, W + 14, TopY]),
	%  a caption per span lane, in the gutter to its left
	forall(member(sbar(_, _, SL, _, _, SY), SBoxes),
	       ( span_lane_h(LH), span_gutter(GW), CapX is -GW,
		 CapY is SY + LH - 2,
		 format(',~n\t[type:text, point:[~2f, ~2f], content:~q, fontSize:11, fillColor:\'#8b94a6\']',
			[CapX, CapY, SL]) )),
	%  A SOCKET per cell: the dim outline of the place a box will fill, and
	%  its caption, drawn whether or not the fluent holds. A lamp that is
	%  off then looks off rather than looking like a picture that failed to
	%  draw, and a keyed fluent's five places are visible before any of them
	%  is filled (the review's R2).
	forall(( member(placed(gauge(_, _, _, _, GL, _, _), Cells), GBoxes),
		 member(cell(Key, GX, GY, GW, GHh), Cells) ),
	       ( socket_caption(GL, Key, Cap),
		 format(',~n\t[type:rectangle, from:[~2f, ~2f], to:[~2f, ~2f], strokeColor:\'#333a48\']',
			[GX, GY, GX + GW, GY + GHh]),
		 format(',~n\t[type:text, point:[~2f, ~2f], content:~q, fontSize:~w, fillColor:\'#8b94a6\']',
			[GX, GY + GHh + GLG + GLH, Cap, GLH]) )),
	forall(member(box(_, Label, X, Y, BW, BH), Boxes),
	       ( format(',~n\t[type:rectangle, from:[~2f, ~2f], to:[~2f, ~2f], strokeColor:\'#3a4152\']',
			[X, Y, X + BW, Y + BH]),
		 format(',~n\t[type:text, point:[~2f, ~2f], content:~q, fontSize:13, fillColor:\'#8b94a6\']',
			[X + 6, Y + BH - 14, Label]) )),
	render_floor(Stacks, Cols, W),
	forall(member(PG, PGrids), render_grid_cells(PG)),
	( Title == '' -> true
	; format(',~n\t[type:text, point:[0, ~2f], content:~q, fontSize:15, fillColor:\'#dfe3ea\']',
		 [TitleY, Title]) ),
	format('~n\t]).~n').

%	What a socket is called: the fluent's label, and — when the fluent is
%	keyed — which of its keys this place is for.
socket_caption(Label, none, Label) :- !.
socket_caption(Label, Key, Cap) :-
	format(atom(Cap), '~w: ~w', [Label, Key]).

%	The gauges' captions: font size, and the gap between a caption and the
%	box it names.
gauge_label_h(11).
gauge_label_gap(4).

%	The thing the piles stand on, drawn, because a tower floating over
%	nothing reads as a bug in the picture rather than as a table.
render_floor([], _, _) :- !.
render_floor(_, [], _) :- !.
render_floor([stack(_, _, _, _, Grounds)|_], Cols, W) :-
	Cols = [col(_, _, Base)|_],
	floor_h(FH),
	Y0 is Base - FH,
	format(',~n\t[type:rectangle, from:[~2f, ~2f], to:[~2f, ~2f], fillColor:\'#2f3542\', strokeColor:\'#3a4152\']',
	       [-8.0, Y0, W + 8.0, Base]),
	( Grounds = [G|_]
	-> format(',~n\t[type:text, point:[~2f, ~2f], content:~q, fontSize:12, fillColor:\'#8b94a6\']',
		  [-6.0, Y0 - 14.0, G])
	;  true
	).

render_looks(Ms) :-
	format('%  What each thing looks like. `icon:` names one of the built-in icons~n'),
	format('%  (Help ▸ About the icons, fills and objects); the colour is used by the~n'),
	format('%  box and circle shapes.~n'),
	forall(member(m(Id, Icon, Colour, _, _, _), Ms),
	       ( ( Icon == none -> I = box ; I = Icon ),
		 ( Colour == none -> K = '#6aa6ff' ; K = Colour ),
		 format('lps_look(~q, ~q, ~q).~n', [Id, I, K]) )),
	nl,
	format('%  …and what its surface is like, and what it is in three dimensions:~n'),
	format('%  a fill from the pattern library and an object from the 3D catalogue~n'),
	format('%  (Help ▸ About the icons, fills and objects lists both). `none` is a~n'),
	format('%  plain shape: the renderers ignore a name they do not have.~n'),
	forall(member(m(Id, _, _, _, Pattern, Model), Ms),
	       format('lps_style(~q, ~q, ~q).~n', [Id, Pattern, Model])),
	nl.

		 /*******************************
		 *	  three dimensions	*
		 *******************************/

/*  The same plan, standing up.
 *
 *  Until now "Animate in 3D" asked the model to write `display3d/2` with
 *  coordinates in it — which is the job §I.10.4e took away from it in two
 *  dimensions, given back in a space with one more axis to get wrong. What came
 *  out was everything at the origin, or a camera inside a wall.
 *
 *  So: containers become slabs on the ground, laid out by the *same* box flow
 *  that arranges them in 2D — the 2D layout is a floor plan, and (x, y) becomes
 *  (x, z). Things stand on their slab. A stack is a tower, which is what a
 *  tower already was. And the backdrop always has a ground plane, a camera and
 *  a light, because those three are what the model reliably forgot.
 */
render_3d(Plan, Layers, Stacks, Cols, _Gauges, _Spans, Derived, Boxes, GBoxes, SBoxes, Slots, extent(W, H), Text) :-
	plan_title(Plan, Title),
	world_scale(W, H, Stacks, Cols, S, CamR),
	tower_height(Stacks, Cols, TowerH),
	with_output_to(string(Text),
	    ( format('%  Scene generated by the LPS2 assistant: the plan was the model\'s,~n'),
	      format('%  the geometry is this file\'s (src/edges/lps_scene.pl). The same plan~n'),
	      format('%  lays out the 2D scene; here the container grid is a floor plan and~n'),
	      format('%  the things stand up out of it.~n~n'),
	      forall(member(layer(Tmpl, GI, MI, Ms, Shape), Layers),
		     render_layer_3d(Tmpl, GI, MI, Ms, Shape, Derived)),
	      forall(member(St, Stacks), render_stack_3d(St)),
	      forall(member(GB, GBoxes), render_gauge_3d(GB, S, W, H, Derived)),
	      forall(member(SB, SBoxes), render_span_3d(SB, S, W, H)),
	      nl,
	      render_backdrop_3d(Title, Boxes, GBoxes, Stacks, S, W, H, CamR, TowerH),
	      nl,
	      render_cells3(GBoxes, S, W, H),
	      (   Slots == []
	      ->  true
	      ;   format('%  Where each thing stands on its slab, in ground coordinates.~n'),
		  forall(member(slot(G, M, X, Y), Slots),
			 ( to3(X, Y, S, W, H, X3, Z3),
			   format('lps_slot3(~q, ~q, ~4f, ~4f).~n', [G, M, X3, Z3]) )),
		  nl
	      ),
	      render_columns_3d(Cols),
	      all_members(Layers, Stacks, AllMs),
	      render_looks(AllMs)
	    )).

/*  Pixels to metres, and how far back the camera has to stand.
 *
 *  One scale for the whole scene, so that a plan with both containers and a
 *  gauge does not end up with the two at different sizes. `CamR` is a radius
 *  that contains everything, tower included — a camera framed on the floor
 *  plan alone looks at the feet of a seven-block tower. */
world_scale(W, H, Stacks, Cols, S, CamR) :-
	cell(C), cell3(C3),
	S is C3 / C,
	Span is max(W, H) * S,
	tower_height(Stacks, Cols, TH),
	CamR is max(8.0, max(Span, TH * 1.6) * 0.95).

tower_height([], _, 0.0) :- !.
tower_height(_, Cols, H) :- length(Cols, N), pitch3_y(P), H is max(1, N) * P.

%	Centre the floor plan on the origin, and flip y into z: a plan drawn with
%	y upward reads as depth *away* from the camera.
to3(X, Y, S, W, H, X3, Z3) :-
	X3 is (X - W / 2) * S,
	Z3 is (H / 2 - Y) * S.

render_layer_3d(Tmpl, GI, MI, _Ms, Shape, Derived) :-
	arg_text(Tmpl, [GI-'Where', MI-'What'], Name, ArgText),
	cell3(C3),
	Y is C3 / 2 + 0.12,
	( is_derived(Derived, Tmpl) -> Extra = ', opacity:0.45' ; Extra = '' ),
	%  `model:` names an object from the catalogue (ui/models3d) and wins
	%  over the plain shape; `none` is not one of them, so a member with no
	%  model of its own falls back to the box or the sphere exactly as
	%  before. One clause either way — the renderer decides, which is where
	%  the catalogue lives.
	(   Shape == circle
	->  R is C3 / 2,
	    format('display3d(~w(~w), [type:sphere, position:[X, ~4f, Z], radius:~4f,~n\c
\t\t       model:Obj, scale:1.5, pattern:Fill, color:Colour~w, label:What]) :-~n\c
\tlps_slot3(Where, What, X, Z), lps_look(What, _, Colour),~n\c
\tlps_style(What, Fill, Obj).~n~n',
		   [Name, ArgText, Y, R, Extra])
	;   format('display3d(~w(~w), [type:box, position:[X, ~4f, Z], size:[~4f, ~4f, ~4f],~n\c
\t\t       model:Obj, scale:1.5, pattern:Fill, color:Colour~w, label:What]) :-~n\c
\tlps_slot3(Where, What, X, Z), lps_look(What, _, Colour),~n\c
\tlps_style(What, Fill, Obj).~n~n',
		   [Name, ArgText, Y, C3, C3, C3, Extra])
	).

render_stack_3d(stack(Tmpl, MI, SI, _Ms, Grounds)) :-
	arg_text(Tmpl, [SI-'Where', MI-'What'], Name, ArgText),
	cell3(C3), pitch3_y(PY),
	Half is C3 / 2,
	stack_goal(Tmpl, MI, SI, 'T', 'S', OnTS),
	stack_goal(Tmpl, MI, SI, 'S', '_', OnS),
	format('display3d(~w(~w), [type:box, position:[X, Y, 0], size:[~4f, ~4f, ~4f],~n\c
\t\t       color:Colour, label:What]) :-~n\c
\tlps_pile_x3(What, X), lps_pile_top3(Where, BY),~n\c
\tlps_look(What, _, Colour), Y is BY + ~4f.~n~n',
	       [Name, ArgText, C3, C3, C3, Half]),
	render_stack_helpers('3', OnTS, OnS, PY, Grounds).

render_gauge_3d(placed(gauge(Tmpl, VI, KI, _, Label, Colour, Fill), Cells), S, W, H, Derived) :-
	cell3(C3), Yc is C3 / 2,
	%  quoted, for the reason render_gauge/2 gives: a capitalised label is a
	%  variable, and prints as one
	%  a derived fluent is drawn hollow here too: half-transparent, since a
	%  box in three dimensions has no outline to draw instead of a fill
	( is_derived(Derived, Tmpl) -> Extra0 = ', opacity:0.45' ; Extra0 = '' ),
	pattern_prop(Fill, Pat),
	atom_concat(Extra0, Pat, Extra),
	functor(Tmpl, Name0, _),
	(   KI > 0, Cells = [cell(K0, _, _, _, _)|_], K0 \== none
	->  %  KEYED, exactly as in two dimensions: one box per key, standing at
	    %  the place `lps_cell3/5` gives it.
	    (   VI =:= 0
	    ->  arg_text(Tmpl, [KI-'Key'], Name, ArgText), LabelText = Label
	    ;   arg_text(Tmpl, [KI-'Key', VI-'Value'], Name, ArgText), LabelText = 'Value'
	    ),
	    (   VI =:= 0
	    ->  format('display3d(~w(~w), [type:box, position:[X, Y, Z], size:[~4f, ~4f, ~4f],~n\c
\t\t       color:~q~w, label:~q]) :-~n\c
\tlps_cell3(~q, Key, X, Y, Z).~n~n',
		       [Name, ArgText, C3, C3, C3, Colour, Extra, LabelText, Name0])
	    ;   format('display3d(~w(~w), [type:box, position:[X, Y, Z], size:[~4f, ~4f, ~4f],~n\c
\t\t       color:~q~w, label:Value]) :-~n\c
\tlps_cell3(~q, Key, X, Y, Z).~n~n',
		       [Name, ArgText, C3, C3, C3, Colour, Extra, Name0])
	    )
	;   Cells = [Cell|_],
	    cell3_pos(Cell, S, W, H, X3, Z3),
	    (   VI =:= 0
	    ->  lamp_head(Tmpl, Head),
		format('display3d(~w, [type:box, position:[~4f, ~4f, ~4f], size:[~4f, ~4f, ~4f],~n\c
\t\t       color:~q~w, label:~q]).~n~n',
		       [Head, X3, Yc, Z3, C3, C3, C3, Colour, Extra, Label])
	    ;   arg_text(Tmpl, [VI-'Value'], Name, ArgText),
		format('display3d(~w(~w), [type:box, position:[~4f, ~4f, ~4f], size:[~4f, ~4f, ~4f],~n\c
\t\t       color:~q~w, label:(~q:Value)]).~n~n',
		       [Name, ArgText, X3, Yc, Z3, C3, C3, C3, Colour, Extra, Label])
	    )
	).

/*  Where a cell stands in the world: the same place as in two dimensions,
    the floor plan's (x, y) become (x, z), and the row is pushed forward of
    the containers so that the gauges read as a dashboard in front of the
    scene rather than as more things in it.  */
cell3_pos(cell(_, X, Y, GW, GH), S, W, H, X3, Z) :-
	CX is X + GW / 2, CY is Y + GH / 2,
	to3(CX, CY, S, W, H, X3, Z3),
	Z is Z3 + 2.2.

%	Where each keyed box stands, in metres. The 2D table's twin.
render_cells3(Placed, S, W, H) :-
	cell3(C3), Yc is C3 / 2,
	findall(c(N, K, X3, Yc, Z3),
		( member(placed(gauge(Tmpl, _, KI, _, _, _, _), Cells), Placed),
		  KI > 0, functor(Tmpl, N, _),
		  member(Cell, Cells), Cell = cell(K, _, _, _, _), K \== none,
		  cell3_pos(Cell, S, W, H, X3, Z3) ),
		Cs),
	(   Cs == []
	->  true
	;   format('%  Where each keyed box stands: one row per fluent and key.~n'),
	    forall(member(c(N, K, X, Y, Z), Cs),
		   format('lps_cell3(~q, ~q, ~4f, ~4f, ~4f).~n', [N, K, X, Y, Z])),
	    nl
	).

/*  A span in three dimensions: the same act, as a beam lying along x at its
    own lane's depth, its length computed from `Start` and `End` exactly as the
    2D bar's width is. One scene plan, two renderings — which is the rule this
    file exists to keep.  */
render_span_3d(sbar(Tmpl, MI, Label, Colour, Fill, Y), S, W, H) :-
	span_lane_h(LH), span_pitch(Pitch),
	to3(0, Y, S, W, H, X0_3, Z3),
	Z is Z3 - 2.2,
	Yc is LH * S / 2,
	Sc is Pitch * S,
	span_head(Tmpl, MI, Label, Head, LabelText),
	span_head(Tmpl, 0, Label, Anon, _),
	Th is LH * S,
	pattern_prop(Fill, Pat),
	%  A beam for an act that lasted, a stud for an instant — the same
	%  distinction the 2D lane makes, for the same reason (R8).
	format('display3d(happens(~w, S, E), [type:box, position:[X, ~4f, ~4f], size:[L, ~4f, ~4f],~n\c
\t\t       color:~q~w, label:~w]) :-~n\c
\tE > S, X0 is ~4f + S * ~4f, X1 is ~4f + E * ~4f,~n\c
\tL is X1 - X0, X is (X0 + X1) / 2.~n~n',
	       [Head, Yc, Z, Th, Th, Colour, Pat, LabelText,
		X0_3, Sc, X0_3, Sc]),
	Stud is Th / 2,
	format('display3d(happens(~w, S, E), [type:box, position:[X, ~4f, ~4f], size:[~4f, ~4f, ~4f],~n\c
\t\t       color:~q]) :-~n\c
\tE =:= S, X is ~4f + S * ~4f.~n~n',
	       [Anon, Yc, Z, Stud, Stud, Stud, Colour, X0_3, Sc]).

render_columns_3d([]) :- !.
render_columns_3d(Cols) :-
	length(Cols, N),
	pitch3_x(PX),
	format('%  One column per thing, centred on the origin: in the worst case every~n'),
	format('%  thing is standing on the floor in a pile of its own.~n'),
	forall(( nth0(K, Cols, col(Id, _, _)) ),
	       ( X is (K - (N - 1) / 2) * PX,
		 format('lps_column3(~q, ~4f).~n', [Id, X]) )),
	nl.

render_backdrop_3d(Title, Boxes, GBoxes, Stacks, S, W, H, CamR, TowerH) :-
	Ground is max(24.0, CamR * 2.2),
	format('display3d(timeless, [~n'),
	format('\t[type:ground, size:[~4f, ~4f], color:\'#23262e\']', [Ground, Ground]),
	forall(member(box(_, Label, X, Y, BW, BH), Boxes),
	       ( CX is X + BW / 2, CY is Y + BH / 2,
		 to3(CX, CY, S, W, H, X3, Z3),
		 SW is BW * S, SD is BH * S,
		 format(',~n\t[type:box, position:[~4f, 0.05, ~4f], size:[~4f, 0.1, ~4f], color:\'#2f3542\']',
			[X3, Z3, SW, SD]),
		 %  At the slab's near EDGE, not at its middle: a label in the
		 %  middle of a container is a label in the middle of whatever
		 %  is standing in it, and `north` was printed across the goat
		 %  (the review's R10).
		 LZ is Z3 + SD / 2 + 0.5,
		 format(',~n\t[type:text, position:[~4f, 0.35, ~4f], label:~q, color:\'#8b94a6\']',
			[X3, LZ, Label]) )),
	%  The sockets, here a dim pad on the ground with its caption standing
	%  over it: a place that is empty still says whose place it is.
	forall(( member(placed(gauge(_, _, _, _, GL, _, _), Cells), GBoxes),
		 member(Cell, Cells), Cell = cell(Key, _, _, _, _) ),
	       ( cell3_pos(Cell, S, W, H, PX, PZ),
		 socket_caption(GL, Key, Cap),
		 cell3(CC),
		 format(',~n\t[type:box, position:[~4f, 0.05, ~4f], size:[~4f, 0.1, ~4f], color:\'#2f3542\']',
			[PX, PZ, CC, CC]),
		 format(',~n\t[type:text, position:[~4f, ~4f, ~4f], label:~q, color:\'#8b94a6\']',
			[PX, CC + 0.55, PZ, Cap]) )),
	render_floor_3d(Stacks, CamR),
	%  Above the tallest thing there can be, not at a fraction of the camera
	%  radius: a title placed by the camera's reckoning sat inside a
	%  seven-block tower.
	( Title == '' -> true
	; TY is max(CamR * 0.45, TowerH + 1.8),
	  format(',~n\t[type:text, position:[0, ~4f, 0], label:~q, color:\'#dfe3ea\']', [TY, Title]) ),
	CamX is CamR * 0.75, CamY is CamR * 0.70, CamZ is CamR * 1.05,
	LookY is CamR * 0.18,
	format(',~n\t[type:camera, position:[~4f, ~4f, ~4f], lookAt:[0, ~4f, 0]]',
	       [CamX, CamY, CamZ, LookY]),
	LX is CamR * 0.6, LY is CamR * 1.4, LZ is CamR * 0.5,
	format(',~n\t[type:light, position:[~4f, ~4f, ~4f], intensity:1.15]', [LX, LY, LZ]),
	format('~n\t]).~n').

render_floor_3d([], _) :- !.
render_floor_3d([stack(_, _, _, _, Grounds)|_], CamR) :-
	Slab is max(6.0, CamR * 0.9),
	format(',~n\t[type:box, position:[0, -0.1, 0], size:[~4f, 0.2, ~4f], color:\'#2f3542\']',
	       [Slab, 3.0]),
	(   Grounds = [G|_]
	->  Z is 2.4,
	    format(',~n\t[type:text, position:[0, 0.25, ~4f], label:~q, color:\'#8b94a6\']', [Z, G])
	;   true
	).

		 /*******************************
		 *	      grids		*
		 *******************************/

/*  A **grid** is the fifth shape: a fluent that says *where on a map* a thing
 *  is, by coordinates rather than by the name of a place —
 *  `location(Car, X-Y, Heading)` in `examples/self-driving-car1.lps`, or
 *  `at(Robot, X, Y)`. None of the other four can draw it. A container per
 *  coordinate is a hundred boxes with one car in each and no streets; a gauge
 *  shows `2-1` as text; and a plan that knew both were wrong named nothing,
 *  which is how "Animate in 2D" came to refuse the self-driving cars
 *  (`scene_nothing`).
 *
 *  What is static about a grid is its extent and its cells; where a thing is
 *  drawn follows from its coordinates, at draw time, so the geometry is again
 *  a small function over the state (`lps_grid_N/4` below) rather than a slot
 *  table. The extent is the run's: the smallest rectangle holding every
 *  position a member of the grid ever had, one cell of margin around it. The
 *  cells the run visited are drawn filled — the roads, for a program whose
 *  things only move where they may — and the others as a faint outline.
 *
 *  The plan says
 *
 *      "grids": [{"template": "location(Car, Place, Heading)",
 *                 "member_var": "Car",
 *                 "position_var": "Place",        an X-Y pair, or instead
 *                 "x_var": "X", "y_var": "Y",      two number arguments
 *                 "members": [{"id": "mycar", "icon": "car"}, …],
 *                 "label": "streets"}]
 *
 *  and a layer whose "containers" turn out to be X-Y pairs in the run is
 *  promoted to a grid (promote_grids/6), for the same reason promote_stacks/8
 *  exists: the model was reaching for the right idea with the wrong word.
 *
 *  North is up: y grows upward in the scene, as it does in the program.
 */

grid_cell(30).
grid_max_side(60).

plan_grids(Plan, Inst, Grids, Diags) :-
	(   get_dict(grids, Plan, Gs), is_list(Gs)
	->  foldl(read_grid(Inst), Gs, g([], []), g(RevGrids, RevDiags)),
	    reverse(RevGrids, Grids), reverse(RevDiags, Diags)
	;   Grids = [], Diags = []
	).

read_grid(Inst, G, g(Gs, Ds), g(Gs1, Ds1)) :-
	(   is_dict(G),
	    get_dict(template, G, T0), text_atom(T0, TA),
	    catch(term_string(Tmpl, TA, [variable_names(Bs)]), _, fail),
	    compound(Tmpl),
	    get_dict(member_var, G, MV0), text_atom(MV0, MV),
	    arg_index(Tmpl, Bs, MV, MI),
	    grid_position(G, Tmpl, Bs, Pos)
	->  layer_members(G, Ms0),
	    ( get_dict(label, G, L0) -> text_atom(L0, Label) ; functor(Tmpl, Label, _) ),
	    grid_shape(G, Ms0, Shape),
	    grid_from(Inst, Tmpl, MI, Pos, Ms0, Label, Shape, Grid, Ds, Ds1),
	    ( Grid == none -> Gs1 = Gs ; Gs1 = [Grid|Gs] )
	;   Gs1 = Gs,
	    format(atom(M), 'a grid was skipped: it needs template, member_var and either \c
position_var (an X-Y pair) or x_var and y_var, each a variable of the template (~q)', [G]),
	    Ds1 = [diag(warning, scene_bad_grid, none, M, [])|Ds]
	).

grid_position(G, Tmpl, Bs, pair(PI)) :-
	get_dict(position_var, G, PV0), text_atom(PV0, PV),
	arg_index(Tmpl, Bs, PV, PI), !.
grid_position(G, Tmpl, Bs, xy(XI, YI)) :-
	get_dict(x_var, G, XV0), text_atom(XV0, XV),
	get_dict(y_var, G, YV0), text_atom(YV0, YV),
	arg_index(Tmpl, Bs, XV, XI),
	arg_index(Tmpl, Bs, YV, YI).

grid_shape(G, Ms, Shape) :-
	(   get_dict(shape, G, S0) -> text_atom(S0, Shape)
	;   Ms \== [], forall(member(m(_, I, _, _, _, _), Ms), I \== none) -> Shape = raster
	;   Shape = circle
	).

/*  The grid, measured on the run. Without positions there is nothing to
    measure and nothing to draw, and saying so beats a map of one cell. The
    members are the plan's, and otherwise the things the run placed on it. */
grid_from(Inst, Tmpl, MI, Pos, Ms0, Label, Shape, Grid, Ds, Ds1) :-
	run_instances(Inst, Tmpl, Fs),
	findall(X-Y, ( member(F, Fs), fluent_xy(F, Pos, X, Y) ), XYs0),
	sort(XYs0, XYs),
	(   XYs == []
	->  Grid = none,
	    format(atom(M), 'a grid was skipped: the run gives `~w` no position that is \c
a pair of numbers, so there is no map to draw', [Tmpl]),
	    Ds1 = [diag(warning, scene_grid_no_positions, none, M, [])|Ds]
	;   grid_extent(XYs, MinX, MaxX, MinY, MaxY),
	    grid_max_side(Max),
	    (   MaxX - MinX + 1 > Max ; MaxY - MinY + 1 > Max )
	->  Grid = none,
	    format(atom(M), 'a grid was skipped: `~w` ranges over ~w by ~w cells, more \c
than ~w a side', [Tmpl, MaxX - MinX + 1, MaxY - MinY + 1, Max]),
	    Ds1 = [diag(warning, scene_grid_too_big, none, M, [])|Ds]
	;   grid_extent(XYs, MinX, MaxX, MinY, MaxY),
	    (   Ms0 == []
	    ->  findall(Id, ( member(F, Fs), arg(MI, F, Id), atomic(Id) ), Ids0),
		dedup(Ids0, Ids),
		findall(m(Id, none, none, Id, none, none), member(Id, Ids), Ms)
	    ;   Ms = Ms0
	    ),
	    Grid = grid(Tmpl, MI, Pos, Ms, Label, Shape, ext(MinX, MaxX, MinY, MaxY, XYs)),
	    Ds1 = Ds
	).

%	The run's positions, with one cell of margin all round.
grid_extent(XYs, MinX, MaxX, MinY, MaxY) :-
	findall(X, member(X-_, XYs), Xs), findall(Y, member(_-Y, XYs), Ys),
	min_list(Xs, X0), max_list(Xs, X1), min_list(Ys, Y0), max_list(Ys, Y1),
	MinX is X0 - 1, MaxX is X1 + 1, MinY is Y0 - 1, MaxY is Y1 + 1.

fluent_xy(F, pair(PI), X, Y) :- arg(PI, F, P), nonvar(P), P = X-Y, number(X), number(Y).
fluent_xy(F, xy(XI, YI), X, Y) :- arg(XI, F, X), arg(YI, F, Y), number(X), number(Y).

/*  A layer whose containers are coordinates, drawn as the grid it is.

    The test is the run's, not the plan's: every value the run gave the
    layer's place argument is a pair of numbers. `loc(Object, Where)` with
    `Where` a room name stays a layer; `location(Car, Place, _)` with `Place`
    ranging over 2-1, 2-2, … becomes a map. */
promote_grids(Inst, Layers0, Layers, Grids0, Grids, Diags) :-
	foldl(promote_grid(Inst), Layers0, p([], Grids0, []), p(RevL, Grids, Diags0)),
	reverse(RevL, Layers), reverse(Diags0, Diags).

promote_grid(Inst, L, p(Ls, Gs, Ds), p(Ls1, Gs1, Ds1)) :-
	L = layer(Tmpl, GI, MI, Ms, Shape),
	(   \+ ( member(grid(T2, _, _, _, _, _, _), Gs), T2 =@= Tmpl ),
	    run_instances(Inst, Tmpl, Fs), Fs \== [],
	    forall(member(F, Fs), fluent_xy(F, pair(GI), _, _))
	->  functor(Tmpl, Name, _),
	    ( Shape == box -> GShape = circle ; GShape = Shape ),
	    grid_from(Inst, Tmpl, MI, pair(GI), Ms, Name, GShape, Grid, Ds, Ds0),
	    (   Grid == none
	    ->  Ls1 = [L|Ls], Gs1 = Gs, Ds1 = Ds0
	    ;   Ls1 = Ls, append(Gs, [Grid], Gs1),
		copy_term(Tmpl, TN), numbervars(TN, 0, _),
		format(atom(M), 'a layer was drawn as a grid instead: every place the run \c
gave `~p` is a pair of coordinates, so it is a map, not a set of containers', [TN]),
		Ds1 = [diag(info, scene_layer_to_grid, none, M, [])|Ds0]
	    )
	;   Ls1 = [L|Ls], Gs1 = Gs, Ds1 = Ds
	).

/*  Grids are drawn in two dimensions. A map in three would be the same map
    on the floor of the set; until that is written, a 3D scene says it left
    the grid out rather than drawing nothing where the map should be. */
grids_for(twod, Grids, Grids, []) :- !.
grids_for(threed, [], [], []) :- !.
grids_for(threed, _, [], [diag(warning, scene_grid_2d_only, none,
	'a grid (things at coordinates on a map) is drawn in 2D only; this 3D scene leaves it out', [])]).

/*  Grids are stacked one above the other, above whatever is below them. */
grid_layout([], H, [], extent(0, H)) :- !.
grid_layout(Grids, H0, PGrids, extent(W, H)) :-
	grid_cell(C),
	( H0 > 0 -> group_gap(GG), Base is H0 + GG ; Base = 0 ),
	grid_place(Grids, 1, C, Base, PGrids, 0, W, H).

grid_place([], _, _, Y, [], W, W, Y).
grid_place([G|Gs], K, C, Y, [pgrid(G, K, 0, Y, C)|Ps], W0, W, H) :-
	G = grid(_, _, _, _, _, _, ext(MinX, MaxX, MinY, MaxY, _)),
	GW is (MaxX - MinX + 1) * C,
	GH is (MaxY - MinY + 1) * C,
	W1 is max(W0, GW),
	title_h(TH), group_gap(GG),
	Y1 is Y + GH + TH + GG,
	K1 is K + 1,
	grid_place(Gs, K1, C, Y1, Ps, W1, W, H).

%	The thing, at the centre of its cell.
render_grid(pgrid(grid(Tmpl, MI, Pos, _, _, Shape, _), K, _, _, C), Derived) :-
	(   Pos = pair(PI)
	->  arg_text(Tmpl, [PI-'GX-GY', MI-'What'], Name, ArgText)
	;   Pos = xy(XI, YI),
	    arg_text(Tmpl, [XI-'GX', YI-'GY', MI-'What'], Name, ArgText)
	),
	Half is C / 2 - 2,
	( is_derived(Derived, Tmpl) -> Paint = 'strokeColor' ; Paint = 'fillColor' ),
	cell(Cell), Scale is 0.5 * C / Cell,
	(   Shape == raster
	->  %  the 2D renderer centres an icon on its position (ui/src/panes/scene2d.js)
	    format('display(~w(~w), [type:raster, icon:Icon, position:[CX, CY], scale:~3f]) :-~n\c
\tlps_grid_~w(GX, GY, CX, CY),~n\c
\tlps_look(What, Icon, _).~n~n', [Name, ArgText, Scale, K])
	;   Shape == box
	->  format('display(~w(~w), [type:rectangle, from:[X0, Y0], to:[X1, Y1],~n\c
\t\t     ~w:Colour, label:What]) :-~n\c
\tlps_grid_~w(GX, GY, CX, CY),~n\c
\tX0 is CX - ~2f, Y0 is CY - ~2f, X1 is CX + ~2f, Y1 is CY + ~2f,~n\c
\tlps_look(What, _, Colour).~n~n', [Name, ArgText, Paint, K, Half, Half, Half, Half])
	;   format('display(~w(~w), [type:circle, center:[CX, CY], radius:~2f,~n\c
\t\t     ~w:Colour, label:What]) :-~n\c
\tlps_grid_~w(GX, GY, CX, CY),~n\c
\tlps_look(What, _, Colour).~n~n', [Name, ArgText, Half, Paint, K])
	).

%	Where a cell's centre is: the one piece of arithmetic a grid needs.
render_grid_helper(pgrid(grid(_, _, _, _, _, _, ext(MinX, _, MinY, _, _)), K, OX, OY, C)) :-
	format('%  Where the cell at (X, Y) of grid ~w is drawn: its centre. North is up.~n', [K]),
	format('lps_grid_~w(X, Y, CX, CY) :-~n\c
\tnumber(X), number(Y),~n\c
\tCX is ~2f + (X - ~w + 0.5) * ~w,~n\c
\tCY is ~2f + (Y - ~w + 0.5) * ~w.~n~n', [K, OX, MinX, C, OY, MinY, C]).

%	The map itself, in the backdrop: every cell, the visited ones filled,
%	and the grid's name above it.
render_grid_cells(pgrid(grid(_, _, _, _, Label, _, ext(MinX, MaxX, MinY, MaxY, XYs)), _, OX, OY, C)) :-
	forall(( between(MinX, MaxX, X), between(MinY, MaxY, Y) ),
	       ( X0 is OX + (X - MinX) * C, Y0 is OY + (Y - MinY) * C,
		 X1 is X0 + C, Y1 is Y0 + C,
		 (   memberchk(X-Y, XYs)
		 ->  format(',~n\t[type:rectangle, from:[~2f, ~2f], to:[~2f, ~2f], fillColor:\'#2f3542\', strokeColor:\'#3a4152\']',
			    [X0, Y0, X1, Y1])
		 ;   format(',~n\t[type:rectangle, from:[~2f, ~2f], to:[~2f, ~2f], strokeColor:\'#232835\']',
			    [X0, Y0, X1, Y1])
		 ) )),
	TY is OY + (MaxY - MinY + 1) * C + 6,
	format(',~n\t[type:text, point:[~2f, ~2f], content:~q, fontSize:13, fillColor:\'#8b94a6\']',
	       [OX, TY, Label]).

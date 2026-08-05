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
 * ## Three shapes, not two
 *
 * A plan says one or more of three things, and the third was added because the
 * first two made blocks world unreadable:
 *
 *   * **containers and members** — a fluent that says *where a thing is*:
 *     `loc(Object, Where)`, `at(Robot, Room)`. Static geometry: a grid of
 *     slots, one per (container, thing) pair.
 *   * **gauges** — a fluent that says *what value something has*:
 *     `heating(on)`, `balance(alice, 100)`.
 *   * **stacks** — a fluent that says *what a thing is standing on*:
 *     `on(Block, Support)`, where the support is another thing of the same
 *     kind. Read as containers, `on(a,b), on(b,c), …` draws seven boxes each
 *     holding one small square, every block appears twice — once as a
 *     container and once as a thing — and a tower is nowhere on the screen.
 *
 * A stack cannot use the slot table, and that is the interesting part. How high
 * a block is drawn depends on how many blocks are underneath it, which changes
 * every cycle, so the geometry cannot be precomputed at all: what is generated
 * is a small *recursion over the state*, the same one `examples/blocks3d.lps`
 * writes by hand. `state/1` is the engine's own view of the current state
 * (src/core/lps_builtins.pl) and the scene layer points it at the cycle being
 * drawn, so the tower in the picture is the tower at that cycle.
 *
 * A plan that calls a support relation "containers" is *promoted* rather than
 * rejected — see promote_stacks/7. A model that has not read this file's prompt
 * still gets a tower.
 */

:- module(lps_scene, [
	scene_clauses/3,         % +Plan (dict), -Text, -Diags
	scene_clauses/4          % +Plan (dict), +Kind, -Text, -Diags
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
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
scene_clauses(Plan, Kind, Text, Diags) :-
	plan_groups(Plan, Groups0, D1),
	plan_layers(Plan, Layers0, D2),
	plan_gauges(Plan, Gauges, D3),
	plan_stacks(Plan, Stacks0, D4),
	promote_stacks(Groups0, Layers0, Stacks0, Groups, Layers, Stacks, D5),
	append([D1, D2, D3, D4, D5], Diags0),
	(   Groups == [], Gauges == [], Stacks == []
	->  Diags = [diag(error, scene_nothing, none,
			  'the plan names no containers, gauges or stacks, so there is \c
nothing to lay out — a fluent whose argument is a *place* is a container, one whose \c
argument is a *value* is a gauge, and one whose argument is another thing of the same \c
kind is a stack', [])|Diags0],
	    Text = ""
	;   members_of(Layers, Members),
	    layout(Groups, Members, Plan, Boxes, Slots, extent(W0, H0)),
	    stack_layout(Stacks, H0, Cols, extent(W1, H1)),
	    W2 is max(W0, W1),
	    gauge_layout(Gauges, H1, GBoxes, H),
	    render(Kind, Plan, Layers, Stacks, Cols, Gauges, Boxes, GBoxes, Slots,
		   extent(W2, H), Text),
	    ( Groups == [] -> Diags = Diags0
	    ; Layers == [] -> Diags = [diag(warning, scene_no_layers_for_groups, none,
					    'the plan has containers but no layer putting anything in them', [])|Diags0]
	    ; Diags = Diags0 )
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
plan_layers(Plan, Layers, Diags) :-
	(   get_dict(layers, Plan, Ls), is_list(Ls)
	->  foldl(read_layer, Ls, l([], []), l(RevLayers, RevDiags)),
	    reverse(RevLayers, Layers), reverse(RevDiags, Diags)
	;   Layers = [], Diags = []
	).

read_layer(L, l(Ls, Ds), l(Ls1, Ds1)) :-
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
	    Ls1 = [layer(Tmpl, GI, MI, Ms, Sh)|Ls], Ds1 = Ds
	;   Ls1 = Ls,
	    format(atom(M), 'a layer was skipped: it needs template, group_var and \c
member_var, and both variables must appear in the template (~q)', [L]),
	    Ds1 = [diag(warning, scene_bad_layer, none, M, [])|Ds]
	).

layer_members(L, Ms) :-
	(   get_dict(members, L, Xs), is_list(Xs)
	->  findall(m(Id, Icon, Colour, Label),
		    ( member(X, Xs), member_spec(X, Id, Icon, Colour, Label) ), Ms)
	;   Ms = []
	).

member_spec(X, Id, Icon, Colour, Label) :-
	is_dict(X), !,
	get_dict(id, X, I0), text_atom(I0, Id),
	( get_dict(icon, X, C0) -> text_atom(C0, Icon) ; Icon = none ),
	( get_dict(color, X, K0) -> text_atom(K0, Colour) ; Colour = none ),
	( get_dict(label, X, L0) -> text_atom(L0, Label) ; Label = Id ).
member_spec(X, Id, none, none, Id) :- text_atom(X, Id).

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
plan_gauges(Plan, Gauges, Diags) :-
	(   get_dict(gauges, Plan, Gs), is_list(Gs)
	->  foldl(read_gauge, Gs, l([], []), l(RevGs, RevDs)),
	    reverse(RevGs, Gauges), reverse(RevDs, Diags)
	;   Gauges = [], Diags = []
	).

read_gauge(G, l(Gs, Ds), l(Gs1, Ds1)) :-
	(   is_dict(G),
	    get_dict(template, G, T0), text_atom(T0, TA),
	    catch(term_string(Tmpl, TA, [variable_names(Bs)]), _, fail),
	    compound(Tmpl),
	    get_dict(value_var, G, VV0), text_atom(VV0, VV),
	    arg_index(Tmpl, Bs, VV, VI)
	->  functor(Tmpl, Name, _),
	    ( get_dict(label, G, L0) -> text_atom(L0, Label) ; Label = Name ),
	    ( get_dict(color, G, C0) -> text_atom(C0, Colour) ; Colour = '#2f3542' ),
	    Gs1 = [gauge(Tmpl, VI, Label, Colour)|Gs], Ds1 = Ds
	;   Gs1 = Gs,
	    format(atom(M), 'a gauge was skipped: it needs template and value_var, \c
and the variable must appear in the template (~q)', [G]),
	    Ds1 = [diag(warning, scene_bad_gauge, none, M, [])|Ds]
	).

members_of(Layers, Members) :-
	findall(Id, ( member(layer(_, _, _, Ms, _), Layers), member(m(Id, _, _, _), Ms) ), Ids0),
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
promote_stacks(Groups, Layers, Stacks0, Groups1, Layers1, Stacks, Diags) :-
	findall(N/A, ( member(stack(T, _, _, _, _), Stacks0), functor(T, N, A) ), Already),
	promote_(Layers, Groups-Already, [], RevKept, [], RevFound, [], RevDiags),
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
		      ( member(m(Id, _, _, _), Ms) ; member(Id, Gs) ) ), Ids0),
	sort(Ids0, Ids).

promote_([], _, Kept, Kept, Fs, Fs, Ds, Ds).
promote_([L|Ls], Groups-Already, Kept0, Kept, Ss0, Ss, Ds0, Ds) :-
	L = layer(Tmpl, GI, MI, Ms, _Shape),
	functor(Tmpl, TN, TA),
	(   \+ memberchk(TN/TA, Already),
	    looks_like_stack(Groups, Ms, Shared, Floor)
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
	promote_(Ls, Groups-Already, Kept1, Kept, Ss1, Ss, Ds1, Ds).

looks_like_stack(Groups, Ms, Shared, Floor) :-
	findall(Id, member(g(Id, _), Groups), GIds0), sort(GIds0, GIds),
	GIds \== [],
	findall(Id, member(m(Id, _, _, _), Ms), MIds0), sort(MIds0, MIds),
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
		( nth0(K, Ms, m(Id, _, _, _)), X is K * PX + C / 2 ),
		Cols),
	W is N * PX - (PX - C),
	H is Base + N * PY.

%	One row of gauge boxes, above whatever the containers occupy.
gauge_layout([], H, [], H) :- !.
gauge_layout(Gauges, H0, Boxes, H) :-
	GW = 150, GH = 40, GG = 12,
	( H0 =:= 0 -> Y = 0 ; Y is H0 + 24 ),
	findall(gbox(Tmpl, VI, Label, Colour, X, Y, GW, GH),
		( nth0(K, Gauges, gauge(Tmpl, VI, Label, Colour)),
		  X is K * (GW + GG) ),
		Boxes),
	H is Y + GH.

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
render(twod, Plan, Layers, Stacks, Cols, Gauges, Boxes, GBoxes, Slots, Extent, Text) :- !,
	render_2d(Plan, Layers, Stacks, Cols, Gauges, Boxes, GBoxes, Slots, Extent, Text).
render(threed, Plan, Layers, Stacks, Cols, Gauges, Boxes, GBoxes, Slots, Extent, Text) :-
	render_3d(Plan, Layers, Stacks, Cols, Gauges, Boxes, GBoxes, Slots, Extent, Text).

		 /*******************************
		 *	   two dimensions	*
		 *******************************/

render_2d(Plan, Layers, Stacks, Cols, _Gauges, Boxes, GBoxes, Slots, extent(W0, H), Text) :-
	length(GBoxes, NG),
	( NG =:= 0 -> W = W0 ; W is max(W0, NG * 162 - 12) ),
	( get_dict(title, Plan, T0) -> text_atom(T0, Title) ; Title = '' ),
	cell(C),
	with_output_to(string(Text),
	    ( header_comment(Slots, Stacks),
	      forall(member(layer(Tmpl, GI, MI, Ms, Shape), Layers),
		     render_layer(Tmpl, GI, MI, Ms, Shape, C)),
	      forall(member(S, Stacks), render_stack_2d(S, C)),
	      forall(member(GB, GBoxes), render_gauge(GB)),
	      nl,
	      render_backdrop(Title, Boxes, GBoxes, Stacks, Cols, W, H),
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
	      all_members(Layers, Stacks, AllMs),
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
dedup_members_([m(Id, I, C, L)|Xs], Seen, Out) :-
	(   memberchk(Id, Seen)
	->  Out = Rest, Seen1 = Seen
	;   Out = [m(Id, I, C, L)|Rest], Seen1 = [Id|Seen]
	),
	dedup_members_(Xs, Seen1, Rest).

render_layer(Tmpl, GI, MI, _Ms, Shape, C) :-
	arg_text(Tmpl, [GI-'Where', MI-'What'], Name, ArgText),
	Half is C / 2,
	(   Shape == raster
	->  format('display(~w(~w), [type:raster, icon:Icon, position:[X, Y], scale:0.5]) :-~n\c
\tlps_slot(Where, What, CX, CY), X is CX - ~2f, Y is CY - ~2f,~n\c
\tlps_look(What, Icon, _).~n~n', [Name, ArgText, Half, Half])
	;   Shape == box
	->  format('display(~w(~w), [type:rectangle, from:[X0, Y0], to:[X1, Y1],~n\c
\t\t     fillColor:Colour, label:What]) :-~n\c
\tlps_slot(Where, What, CX, CY),~n\c
\tX0 is CX - ~2f, Y0 is CY - ~2f, X1 is CX + ~2f, Y1 is CY + ~2f,~n\c
\tlps_look(What, _, Colour).~n~n', [Name, ArgText, Half, Half, Half, Half])
	;   format('display(~w(~w), [type:circle, center:[CX, CY], radius:~2f,~n\c
\t\t     fillColor:Colour, label:What]) :-~n\c
\tlps_slot(Where, What, CX, CY),~n\c
\tlps_look(What, _, Colour).~n~n', [Name, ArgText, Half])
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
    block on the floor (the note in examples/blocks3d.lps is about exactly that
    afternoon). */
stack_goal(Tmpl, MI, SI, MVar, SVar, Goal) :-
	arg_text(Tmpl, [MI-MVar, SI-SVar], Name, ArgText),
	format(atom(Goal), 'state(~w(~w))', [Name, ArgText]).

%	The template's arguments, with the named positions replaced and the rest
%	left as fresh anonymous variables.
arg_text(Tmpl, Pairs, Name, ArgText) :-
	Tmpl =.. [Name|Args],
	length(Args, Arity),
	numlist(1, Arity, Is),
	findall(V, ( member(I, Is),
		     ( memberchk(I-V0, Pairs) -> V = V0
		     ; V = '_' ) ), Vs),
	atomic_list_concat(Vs, ', ', ArgText).

render_columns([]) :- !.
render_columns(Cols) :-
	format('%  One column per thing: in the worst case every thing is standing on~n'),
	format('%  the floor in a pile of its own.~n'),
	forall(member(col(Id, X, _), Cols), format('lps_column(~q, ~2f).~n', [Id, X])),
	nl.

%	A gauge is one rule: whatever value the fluent has, in its own box.
render_gauge(gbox(Tmpl, VI, Label, Colour, X, Y, W, H)) :-
	arg_text(Tmpl, [VI-'Value'], Name, ArgText),
	X1 is X + W, Y1 is Y + H,
	format('display(~w(~w), [type:rectangle, from:[~2f, ~2f], to:[~2f, ~2f],~n\c
\t\t     fillColor:~q, label:(~w:Value)]).~n~n',
	       [Name, ArgText, X, Y, X1, Y1, Colour, Label]).

render_backdrop(Title, Boxes, GBoxes, Stacks, Cols, W, H) :-
	format('display(timeless, [~n'),
	format('\t[type:rectangle, from:[-14, -26], to:[~2f, ~2f], strokeColor:\'#2a2f3a\']', [W + 14, H + 46]),
	forall(member(gbox(_, _, GL, _, GX, GY, _, GHh), GBoxes),
	       format(',~n\t[type:text, point:[~2f, ~2f], content:~q, fontSize:11, fillColor:\'#8b94a6\']',
		      [GX, GY + GHh + 4, GL])),
	forall(member(box(_, Label, X, Y, BW, BH), Boxes),
	       ( format(',~n\t[type:rectangle, from:[~2f, ~2f], to:[~2f, ~2f], strokeColor:\'#3a4152\']',
			[X, Y, X + BW, Y + BH]),
		 format(',~n\t[type:text, point:[~2f, ~2f], content:~q, fontSize:13, fillColor:\'#8b94a6\']',
			[X + 6, Y + BH - 14, Label]) )),
	render_floor(Stacks, Cols, W),
	( Title == '' -> true
	; format(',~n\t[type:text, point:[0, ~2f], content:~q, fontSize:15, fillColor:\'#dfe3ea\']',
		 [H + 26, Title]) ),
	format('~n\t]).~n').

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
	format('%  (Help ▸ About the icons); the colour is used by box and circle shapes.~n'),
	forall(member(m(Id, Icon, Colour, _), Ms),
	       ( ( Icon == none -> I = box ; I = Icon ),
		 ( Colour == none -> K = '#6aa6ff' ; K = Colour ),
		 format('lps_look(~q, ~q, ~q).~n', [Id, I, K]) )).

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
render_3d(Plan, Layers, Stacks, Cols, _Gauges, Boxes, GBoxes, Slots, extent(W, H), Text) :-
	( get_dict(title, Plan, T0) -> text_atom(T0, Title) ; Title = '' ),
	world_scale(W, H, Stacks, Cols, S, CamR),
	tower_height(Stacks, Cols, TowerH),
	with_output_to(string(Text),
	    ( format('%  Scene generated by the LPS2 assistant: the plan was the model\'s,~n'),
	      format('%  the geometry is this file\'s (src/edges/lps_scene.pl). The same plan~n'),
	      format('%  lays out the 2D scene; here the container grid is a floor plan and~n'),
	      format('%  the things stand up out of it.~n~n'),
	      forall(member(layer(Tmpl, GI, MI, Ms, Shape), Layers),
		     render_layer_3d(Tmpl, GI, MI, Ms, Shape)),
	      forall(member(St, Stacks), render_stack_3d(St)),
	      forall(member(GB, GBoxes), render_gauge_3d(GB, S, W, H)),
	      nl,
	      render_backdrop_3d(Title, Boxes, Stacks, S, W, H, CamR, TowerH),
	      nl,
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

render_layer_3d(Tmpl, GI, MI, _Ms, Shape) :-
	arg_text(Tmpl, [GI-'Where', MI-'What'], Name, ArgText),
	cell3(C3),
	Y is C3 / 2 + 0.12,
	(   Shape == circle
	->  R is C3 / 2,
	    format('display3d(~w(~w), [type:sphere, position:[X, ~4f, Z], radius:~4f,~n\c
\t\t       color:Colour, label:What]) :-~n\c
\tlps_slot3(Where, What, X, Z), lps_look(What, _, Colour).~n~n',
		   [Name, ArgText, Y, R])
	;   format('display3d(~w(~w), [type:box, position:[X, ~4f, Z], size:[~4f, ~4f, ~4f],~n\c
\t\t       color:Colour, label:What]) :-~n\c
\tlps_slot3(Where, What, X, Z), lps_look(What, _, Colour).~n~n',
		   [Name, ArgText, Y, C3, C3, C3])
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

render_gauge_3d(gbox(Tmpl, VI, Label, Colour, X, _Y, _W, _H), S, W, H) :-
	arg_text(Tmpl, [VI-'Value'], Name, ArgText),
	to3(X, 0, S, W, H, X3, Z3),
	Z is Z3 + 2.2,
	cell3(C3),
	Yc is C3 / 2,
	format('display3d(~w(~w), [type:box, position:[~4f, ~4f, ~4f], size:[~4f, ~4f, ~4f],~n\c
\t\t       color:~q, label:(~w:Value)]).~n~n',
	       [Name, ArgText, X3, Yc, Z, C3, C3, C3, Colour, Label]).

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

render_backdrop_3d(Title, Boxes, Stacks, S, W, H, CamR, TowerH) :-
	Ground is max(24.0, CamR * 2.2),
	format('display3d(timeless, [~n'),
	format('\t[type:ground, size:[~4f, ~4f], color:\'#23262e\']', [Ground, Ground]),
	forall(member(box(_, Label, X, Y, BW, BH), Boxes),
	       ( CX is X + BW / 2, CY is Y + BH / 2,
		 to3(CX, CY, S, W, H, X3, Z3),
		 SW is BW * S, SD is BH * S,
		 format(',~n\t[type:box, position:[~4f, 0.05, ~4f], size:[~4f, 0.1, ~4f], color:\'#2f3542\']',
			[X3, Z3, SW, SD]),
		 format(',~n\t[type:text, position:[~4f, 0.35, ~4f], label:~q, color:\'#8b94a6\']',
			[X3, Z3, Label]) )),
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

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
 */

:- module(lps_scene, [
	scene_clauses/3          % +Plan (dict), -Text, -Diags
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

%!	scene_clauses(+Plan, -Text, -Diags) is det.
%
%	Plan is the dict described in the module header. Text is Prolog source:
%	a slot table, a `display(timeless, …)` backdrop and one `display/2` rule
%	per layer.
scene_clauses(Plan, Text, Diags) :-
	plan_groups(Plan, Groups, D1),
	plan_layers(Plan, Layers, D2),
	append(D1, D2, Diags0),
	(   Groups == []
	->  Diags = [diag(error, scene_no_groups, none,
			  'the plan names no containers, so there is nothing to lay out', [])|Diags0],
	    Text = ""
	;   members_of(Layers, Members),
	    layout(Groups, Members, Plan, Boxes, Slots, Extent),
	    render(Plan, Groups, Layers, Boxes, Slots, Extent, Text),
	    Diags = Diags0
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

plan_layers(Plan, Layers, Diags) :-
	(   get_dict(layers, Plan, Ls), is_list(Ls)
	->  foldl(read_layer, Ls, l([], []), l(RevLayers, RevDiags)),
	    reverse(RevLayers, Layers), reverse(RevDiags, Diags)
	;   Layers = [], Diags = [diag(error, scene_no_layers, none,
				       'the plan has no layers, so no fluent is mapped to anything', [])]
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

members_of(Layers, Members) :-
	findall(Id, ( member(layer(_, _, _, Ms, _), Layers), member(m(Id, _, _, _), Ms) ), Ids0),
	sort(Ids0, Members).

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
	findall(box(Id, Label, X0, Y0, BoxW, BoxH),
		( nth0(K, Groups, g(Id, Label)),
		  ( Dir == row
		  ->  X0 is K * (BoxW + GG), Y0 = 0
		  ;   X0 = 0, Y0 is (NG - 1 - K) * (BoxH + GG) )
		),
		Boxes),
	(   Dir == row
	->  W is NG * BoxW + (NG - 1) * GG, H = BoxH
	;   W = BoxW, H is NG * BoxH + (NG - 1) * GG
	),
	findall(slot(GId, MId, SX, SY),
		( member(box(GId, _, BX, BY, _, _), Boxes),
		  nth0(J, Members, MId),
		  Col is J mod Cols, Row is J // Cols,
		  SX is BX + P + Col * (C + G) + C / 2,
		  %  y grows upward, so row 0 is the *top* row of the grid.
		  SY is BY + P + (Rows - 1 - Row) * (C + G) + C / 2
		),
		Slots).

		 /*******************************
		 *	    rendering		*
		 *******************************/

render(Plan, _Groups, Layers, Boxes, Slots, extent(W, H), Text) :-
	( get_dict(title, Plan, T0) -> text_atom(T0, Title) ; Title = '' ),
	cell(C),
	with_output_to(string(Text),
	    ( format('%  Scene generated by the LPS2 assistant: the plan was the model\'s,~n'),
	      format('%  the geometry is this file\'s (src/edges/lps_scene.pl). Every position~n'),
	      format('%  comes from lps_slot/4 below, so nothing can overlap — move a slot and~n'),
	      format('%  everything that ever sits in it moves with it.~n~n'),
	      forall(member(layer(Tmpl, GI, MI, Ms, Shape), Layers),
		     render_layer(Tmpl, GI, MI, Ms, Shape, C)),
	      nl,
	      render_backdrop(Title, Boxes, W, H),
	      nl,
	      format('%  Where each thing sits in each container. One row per pair, so a~n'),
	      format('%  thing keeps its column wherever it is.~n'),
	      forall(member(slot(G, M, X, Y), Slots),
		     format('lps_slot(~q, ~q, ~2f, ~2f).~n', [G, M, X, Y])),
	      nl,
	      forall(member(layer(_, _, _, Ms2, _), Layers), render_looks(Ms2))
	    )).

render_layer(Tmpl, GI, MI, _Ms, Shape, C) :-
	Tmpl =.. [Name|Args],
	length(Args, Arity),
	numlist(1, Arity, Is),
	findall(V, ( member(I, Is),
		     ( I =:= GI -> V = 'Where'
		     ; I =:= MI -> V = 'What'
		     ; format(atom(V), '_A~w', [I]) ) ), Vs),
	atomic_list_concat(Vs, ', ', ArgText),
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

render_backdrop(Title, Boxes, W, H) :-
	format('display(timeless, [~n'),
	format('\t[type:rectangle, from:[-14, -14], to:[~2f, ~2f], strokeColor:\'#2a2f3a\']', [W + 14, H + 34]),
	forall(member(box(_, Label, X, Y, BW, BH), Boxes),
	       ( format(',~n\t[type:rectangle, from:[~2f, ~2f], to:[~2f, ~2f], strokeColor:\'#3a4152\']',
			[X, Y, X + BW, Y + BH]),
		 format(',~n\t[type:text, point:[~2f, ~2f], content:~q, fontSize:13, fillColor:\'#8b94a6\']',
			[X + 6, Y + BH - 14, Label]) )),
	( Title == '' -> true
	; format(',~n\t[type:text, point:[0, ~2f], content:~q, fontSize:15, fillColor:\'#dfe3ea\']',
		 [H + 12, Title]) ),
	format('~n\t]).~n').

render_looks(Ms) :-
	format('%  What each thing looks like. `icon:` names one of the built-in icons~n'),
	format('%  (Help ▸ About the icons); the colour is used by box and circle shapes.~n'),
	forall(member(m(Id, Icon, Colour, _), Ms),
	       ( ( Icon == none -> I = box ; I = Icon ),
		 ( Colour == none -> K = '#6aa6ff' ; K = Colour ),
		 format('lps_look(~q, ~q, ~q).~n', [Id, I, K]) )).

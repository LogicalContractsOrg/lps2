/* scene_test.pl — the pictures: what is worth drawing, and what gets drawn.

   Three things are checked here, and they are the three halves of
   `docs/project/plans/AnimationPlan.md`:

     §5  `lps_scene_focus/3` — the fluents that tell a run's states apart, the
	 cycles worth a frame, and the states it comes back to. Everything
	 else in this file is keyed on it, and so is the IDE.
     §6  the shapes read out of the SOURCE — a composite event as a span with
	 its own start and end, an intensional fluent drawn as derived, and
	 the order the rules put things in.
     §7  the scene STRIP — one scene per keyframe, with what moved the story
	 on between them.

   Usage:
     ./myswipl.sh -q -g "consult('tools/scene_test.pl')" -g "scene_test:main" -t halt
*/

:- module(scene_test, [main/0]).

:- use_module(library(lists)).
:- use_module('../src/lps').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_explain').
:- use_module('../src/core/lps_diag').
:- use_module('../src/edges/lps_scene').
:- use_module('../src/edges/lps_http').
:- use_module('../src/edges/lps_assistant').

:- dynamic failures/1.
failures(0).

main :-
	retractall(failures(_)), assertz(failures(0)),
	forall(test(Name, Goal), run_test(Name, Goal)),
	failures(N),
	(   N =:= 0
	->  format('~n=== scenes: every case behaves ===~n', [])
	;   format('~n=== scenes: ~w FAILED ===~n', [N]), halt(1)
	).

run_test(Name, Goal) :-
	(   catch(call(Goal), E, (format('  ~w: exception ~q~n', [Name, E]), fail))
	->  format('  ok    ~w~n', [Name])
	;   format('  FAIL  ~w~n', [Name]),
	    retract(failures(N)), N1 is N + 1, assertz(failures(N1))
	).

root(Root) :-
	module_property(scene_test, file(F)),
	file_directory_name(F, Tools), file_directory_name(Tools, Root).

%	A run of one of the repository's own examples, by relative path.
example_run(Rel, S) :-
	root(Root), atomic_list_concat([Root, '/', Rel], File),
	lps_compile(file(File), legacy, [dc], P, D),
	diags_ok(D),
	lps_session_new(P, [dc], S0),
	lps_session_run(S0, end, S, _).

%	A run of a program written here, in the external syntax.
source_run(Source, S) :-
	lps_api:source_terms(Source, Terms, []),
	lps_compile(terms(Terms), legacy, [dc], P, D),
	diags_ok(D),
	lps_session_new(P, [dc], S0),
	lps_session_run(S0, end, S, _).

		 /*******************************
		 *	     the tests		*
		 *******************************/

test('§5 the focus names the fluents that tell the states apart', t_discriminating).
test('§5 the keyframes are the cycles at which the picture changes', t_keyframes).
test('§5 a state the run comes back to is reported as a loop', t_loops).
test('§5 the focus marks each fluent stored or derived', t_derived).
test('§6 a composite event is a subject in its own right, with its interval', t_composite_subject).
test('§6 a span is drawn from the act\'s own start and end', t_span_clause).
test('§6 a derived fluent is drawn as an outline', t_derived_outline).
test('§6 the row follows the order the rules mention things in', t_rule_order).
test('§7 the strip is one scene per keyframe, in order', t_strip_frames).
test('§7 each frame carries what moved the story on to it', t_strip_captions).
test('§7 the strip is the same shape in three dimensions', t_strip_3d).
test('a member\'s fill and object reach both renderings', t_style_tables).
test('a fill named on a gauge or a span reaches its clause', t_style_gauge_span).
test('R1 a keyed fluent gets one box per key', t_keyed_gauge).
test('R1 a keyed lamp gets one box per key', t_keyed_lamp).
test('R2 every cell has a socket in the backdrop, filled or not', t_sockets).
test('R1 a keyed fluent is keyed in three dimensions too', t_keyed_3d).
test('R8 a span lane draws bars for acts and ticks for instants', t_span_ticks).
test('R1 the run decides what is a key and what is a value', t_key_from_run).
test('R7 a near-miss layer is drawn rather than skipped', t_salvaged_layer).
test('R7 what was drawn is reported, and it is not the plan', t_drawn_report).
test('a place shared with another layer\'s things does not make a stack', t_not_promoted_by_run).
test('a stack whose run never piles anything is drawn as containers', t_stack_demoted).
test('a run that piles things keeps its stack', t_stack_kept).
test('the libraries the assistant is told about are the ones that exist', t_catalogues).
test('a thing at coordinates is drawn on a grid measured on the run', t_grid).
test('containers that are all coordinates are drawn as a grid', t_grid_promoted).
test('a 3D scene leaves a grid out and says so', t_grid_3d).

/*  The Underground notice, which is the program the whole plan came from: five
    fluents, of which three change. `in_station` holds from `initially` to the
    end of the run, so it is backdrop — the picture may show it, but nothing is
    missing from a picture that does not.
*/
t_discriminating :-
	example_run('examples/collections/kowalski-book/underground.lps', S),
	lps_session_focus(S, focus(Disc, _, _)),
	forall(member(K, [alerted/0, emergency/1, stopped/0]),
	       memberchk(disc(K, _, _, _), Disc)),
	\+ memberchk(disc(in_station/0, _, _, _), Disc),
	memberchk(disc(emergency/1, emergency(fire), _, stored), Disc).

/*  Eight cycles, four pictures: the opening state, the emergency, the alarm,
    the train stopping. A frame per cycle would draw the same picture twice at
    the start and four times at the end.
*/
t_keyframes :-
	example_run('examples/collections/kowalski-book/underground.lps', S),
	lps_session_focus(S, focus(_, KFs, _)),
	findall(C, member(kf(C, _, _), KFs), Cs),
	Cs == [0, 3, 4, 5],
	%  and each carries what moved the story on
	memberchk(kf(3, _, [emergency_occurs(fire)]), KFs),
	memberchk(kf(0, _, []), KFs).

t_loops :-
	example_run('examples/collections/kowalski-book/underground.lps', S),
	lps_session_focus(S, focus(_, KFs, Loops)),
	%  the opening state holds for three cycles and the closing one for four
	memberchk([0, 1, 2], Loops),
	%  a keyframe knows it is one of them: its state id has several cycles
	memberchk(kf(0, [0, 1, 2], _), KFs).

/*  `p_intensional/2` already knows which fluents are defined by a rule rather
    than set by an event, so the model is never asked: the focus says which,
    and the generator draws those as outlines (§6).
*/
t_derived :-
	source_run("maxTime(3).\n\c
fluents alerted, stopped.\n\c
events alarm.\n\c
actions stop_train.\n\c
alarm initiates alerted.\n\c
stop_train initiates stopped.\n\c
if alerted at T1 then stop_train from T1 to T2.\n\c
emergency_over if stopped.\n\c
observe alarm from 1 to 2.\n", S),
	lps_session_focus(S, focus(Disc, _, _)),
	memberchk(disc(stopped/0, _, _, stored), Disc).

		 /*******************************
		 *	  §6 what the source	*
		 *	     already says	*
		 *******************************/

%	A program with a composite event, and a span drawn for it by hand in
%	the shape the generator writes.
span_program("maxTime(6).\n\c
fluents at(_).\n\c
actions step(_).\n\c
events journey(_).\n\c
initially at(start).\n\c
step(P) updates Old to P in at(Old).\n\c
journey(P) from T1 to T3 if step(mid) from T1 to T2, step(P) from T2 to T3.\n\c
if at(start) at T1 then journey(finish) from T1 to T3.\n\c
display(happens(journey(P), S, E), [type:rectangle, from:[X0, 0], to:[X1, 14],\n\c
\t\t fillColor:'#4c6ef5', label:P]) :-\n\c
\tX0 is S * 24, X1 is max(E * 24, X0 + 8).\n\c
display(at(P), [type:circle, center:[10, 40], radius:6, fillColor:green, label:P]).\n").

/*  The engine records a composite with its own interval, and the scene offers
    it to `display/2` as a subject: an ACT, with a beginning and an end, which
    is the one narrative shape a program can state and the picture could not
    draw. It stays on the chart after it is over — a reader at cycle 5 wants
    the acts that got the run there, not an empty lane.
*/
t_composite_subject :-
	span_program(Src), source_run(Src, S),
	lps_session_scene(S, 5, scene(_, _, Items)),
	memberchk(visual(composite, happens(journey(finish), 1, 3), _), Items),
	%  and not before it began
	lps_session_scene(S, 0, scene(_, _, Items0)),
	\+ memberchk(visual(composite, _, _), Items0).

%	The bar's extent is the act's own: 1 to 3 at 24 pixels a cycle.
t_span_clause :-
	span_program(Src), source_run(Src, S),
	lps_session_scene(S, 5, scene(_, _, Items)),
	memberchk(visual(composite, happens(journey(finish), _, _), Props), Items),
	memberchk(from:[X0, _], Props), memberchk(to:[X1, _], Props),
	X0 =:= 24, X1 =:= 72.

/*  A fluent the program DERIVES is drawn as an outline. The model is not asked
    which: `p_intensional/2` knows, so the layout reads it off the program
    (scene_options/4 in lps_assistant.pl passes it in).
*/
t_derived_outline :-
	Plan = _{title: "t", groups: [], layers: [],
		 gauges: [_{template: "stored_one", label: "stored"},
			  _{template: "derived_one", label: "derived"}]},
	scene_clauses(Plan, twod, [derived([derived_one/0])], Text, _),
	sub_string(Text, _, _, _, "display(derived_one, [type:rectangle"),
	%  the derived one is outlined, the stored one filled
	once(( sub_string(Text, B, _, _, "display(derived_one"),
	       sub_string(Text, B, 200, _, Chunk) )),
	sub_string(Chunk, _, _, _, "strokeColor"),
	\+ sub_string(Chunk, _, _, _, "fillColor"),
	once(( sub_string(Text, B2, _, _, "display(stored_one"),
	       sub_string(Text, B2, 200, _, Chunk2) )),
	sub_string(Chunk2, _, _, _, "fillColor").

/*  Two fluents that appear in one rule belong side by side, and the program
    says which those are. The plan below lists them in the other order on
    purpose: the layout re-orders, the model does not have to.
*/
t_rule_order :-
	Plan = _{title: "t", groups: [], layers: [],
		 gauges: [_{template: "c", label: "c"},
			  _{template: "a", label: "a"},
			  _{template: "b", label: "b"}]},
	scene_clauses(Plan, twod, [order([a/0, b/0, c/0])], Text, _),
	sub_string(Text, Pa, _, _, "display(a,"),
	sub_string(Text, Pb, _, _, "display(b,"),
	sub_string(Text, Pc, _, _, "display(c,"),
	Pa < Pb, Pb < Pc.

		 /*******************************
		 *	  §7 the strip		*
		 *******************************/

%	The `scenes` operation, which is what the IDE's "Scenes" button asks
%	for: the run as pictures rather than as a canvas to scrub through.
strip(Source, Kind, Reply) :-
	source_run(Source, S),
	register_session(S, Id),
	lps_api:operation("scenes", _{session: Id, kind: Kind}, Reply).

register_session(S, Id) :-
	lps_api:register_session(S, Id).

t_strip_frames :-
	span_program(Src), strip(Src, "2d", R),
	get_dict(ok, R, true),
	get_dict(frames, R, Frames),
	findall(C, ( member(F, Frames), get_dict(cycle, F, C) ), Cs),
	Cs == [0, 2, 3],
	%  every frame carries the picture at its own cycle
	forall(member(F, Frames), ( get_dict(items, F, I), I \== [] )).

/*  The caption is computed from the trace, not written: the events at that
    cycle and the fluents that began, ended or changed value with them. A
    sentence made of those cannot say anything the run did not do.
*/
t_strip_captions :-
	span_program(Src), strip(Src, "2d", R),
	get_dict(frames, R, Frames),
	member(F, Frames), get_dict(cycle, F, 2), !,
	get_dict(events, F, ["step(mid)"]),
	get_dict(updated, F, ["at(start)-at(mid)"]),
	get_dict(began, F, []),
	%  and the opening frame is a state the run sits in for more than a cycle
	member(F0, Frames), get_dict(cycle, F0, 0), !,
	get_dict(returns, F0, true).

t_strip_3d :-
	span_program(Src), strip(Src, "3d", R),
	get_dict(kind, R, "3d"),
	get_dict(frames, R, Frames),
	length(Frames, 3),
	%  this program has no display3d clauses, so every frame is empty — and
	%  that is an answer (the pane offers to write them), not a failure
	forall(member(F, Frames), ( get_dict(items, F, I), I == [] )).

		 /*******************************
		 *	 fills and objects	*
		 *******************************/

/*  The two libraries beside the icons: a `pattern` fills a surface (what it is
    LIKE) and a `model` is a named 3D object (what it IS). Both are named per
    member in the plan and reach the clauses through one table, `lps_style/3`,
    so a plan that names neither draws exactly what it drew before — `none` is
    not a pattern and not a model, and the renderers ignore a name they do not
    have.
*/
style_plan(_{title: "river", groups: [_{id: "south"}, _{id: "north"}],
	     layers: [_{template: "loc(Object, Where)", group_var: "Where",
			member_var: "Object", shape: "box",
			members: [_{id: "wolf", pattern: "hatch", model: "animal"},
				  _{id: "cabbage"}]}]}).

t_style_tables :-
	style_plan(Plan),
	scene_clauses(Plan, twod, [], Text2, _),
	sub_string(Text2, _, _, _, "lps_style(wolf, hatch, animal)"),
	sub_string(Text2, _, _, _, "lps_style(cabbage, none, none)"),
	sub_string(Text2, _, _, _, "pattern:Fill"),
	sub_string(Text2, _, _, _, "lps_style(What, Fill, _)"),
	scene_clauses(Plan, threed, [], Text3, _),
	sub_string(Text3, _, _, _, "model:Obj, scale:1.5, pattern:Fill"),
	sub_string(Text3, _, _, _, "lps_style(What, Fill, Obj)"),
	sub_string(Text3, _, _, _, "lps_style(wolf, hatch, animal)").

t_style_gauge_span :-
	Plan = _{title: "t", groups: [], layers: [],
		 gauges: [_{template: "load(V)", value_var: "V", label: "load",
			    pattern: "stripes"},
			  _{template: "alerted", label: "alerted"}],
		 spans: [_{template: "trip(To)", label: "trip", pattern: "waves"}]},
	scene_clauses(Plan, twod, [], Text, _),
	sub_string(Text, _, _, _, "pattern:stripes"),
	sub_string(Text, _, _, _, "pattern:waves"),
	%  the lamp named none, so it says nothing about a pattern at all
	once(( sub_string(Text, B, _, _, "display(alerted"),
	       sub_string(Text, B, 140, _, Lamp) )),
	\+ sub_string(Lamp, _, _, _, "pattern"),
	scene_clauses(Plan, threed, [], T3, _),
	sub_string(T3, _, _, _, "pattern:stripes").

/*  R1: a fluent that has a key — `balance(Who, Amount)`, `available(Fork)`,
    `fire(Room)` — gets one place per key. `display/2` draws the FIRST solution
    for a subject and no more, so one box for five free forks is not a thin
    picture but a wrong one: it showed fork2 and painted the other four
    underneath it.
*/
keyed_plan(_{title: "bank", groups: [], layers: [],
	     gauges: [_{template: "balance(Who, Amount)", value_var: "Amount",
			key_var: "Who", keys: ["alice", "bob"], label: "balance"},
		      _{template: "frozen(Who)", key_var: "Who",
			keys: ["alice", "bob"], label: "frozen"}]}).

t_keyed_gauge :-
	keyed_plan(Plan),
	scene_clauses(Plan, twod, [], Text, _),
	%  one clause, placed by the cell table — not one clause per key
	sub_string(Text, _, _, _, "lps_cell(balance, Key, X0, Y0, X1, Y1)"),
	sub_string(Text, _, _, _, "label:Value"),
	%  and a place for each key, at different x
	sub_string(Text, _, _, _, "lps_cell(balance, alice,"),
	sub_string(Text, _, _, _, "lps_cell(balance, bob,"),
	%  …in places of their own: the second key does not start where the
	%  first one does
	sub_string(Text, _, _, _, "lps_cell(balance, alice, 0.00,"),
	\+ sub_string(Text, _, _, _, "lps_cell(balance, bob, 0.00,"),
	\+ sub_string(Text, _, _, _, "lps_cell(frozen, alice, 0.00,").

t_keyed_lamp :-
	keyed_plan(Plan),
	scene_clauses(Plan, twod, [], Text, _),
	%  a lamp keyed the same way: no value to show, so the box says the
	%  label and the caption says which one it is
	sub_string(Text, _, _, _, "lps_cell(frozen, Key, X0, Y0, X1, Y1)"),
	sub_string(Text, _, _, _, "label:frozen"),
	sub_string(Text, _, _, _, "lps_cell(frozen, alice,").

/*  R2: the empty socket. A lamp that is off used to leave its caption hanging
    over nothing, which reads as a picture that failed rather than as a fluent
    that does not hold. The backdrop draws the outline of every place, so off
    looks like off.
*/
t_sockets :-
	keyed_plan(Plan),
	scene_clauses(Plan, twod, [], Text, _),
	once(( sub_string(Text, B, _, _, "display(timeless"),
	       sub_string(Text, B, _, 0, Back) )),
	sub_string(Back, _, _, _, "content:'frozen: alice'"),
	sub_string(Back, _, _, _, "content:'balance: bob'"),
	%  a dim outline per cell: four cells, four sockets
	aggregate_all(count, sub_string(Back, _, _, _, "strokeColor:'#333a48'"), 4).

t_keyed_3d :-
	keyed_plan(Plan),
	scene_clauses(Plan, threed, [], Text, _),
	sub_string(Text, _, _, _, "lps_cell3(balance, Key, X, Y, Z)"),
	sub_string(Text, _, _, _, "lps_cell3(balance, alice,"),
	sub_string(Text, _, _, _, "lps_cell3(frozen, bob,"),
	%  and the sockets are there too, as pads with their captions over them
	sub_string(Text, _, _, _, "label:'frozen: alice'").

/*  R1, the half the model cannot be trusted with: WHICH argument is the key.
    A plan may call the same argument the value and the key, or call a key a
    value (`available(Fork)`, `value_var: "Fork"` — both models did this). The
    run settles it: a fluent that holds of several of its instances at the same
    cycle is a set of things and wants a box each, and one that never does is a
    value and wants one box. Nothing in the source says this; the trace says it
    exactly.
*/
forks(Inst) :-
	Inst = ['available'/1-inst([available(fork1), available(fork2)], 2)].

t_key_from_run :-
	forks(Inst),
	%  the plan calls the fork a VALUE…
	P1 = _{title: "t", groups: [], layers: [],
	       gauges: [_{template: "available(Fork)", value_var: "Fork", label: "free"}]},
	scene_clauses(P1, twod, [instances(Inst)], T1, _),
	sub_string(T1, _, _, _, "lps_cell(available, Key, X0, Y0, X1, Y1)"),
	sub_string(T1, _, _, _, "lps_cell(available, fork2,"),
	%  …and no lone variable anywhere in the clause it generated
	\+ sub_string(T1, _, _, _, "label:Value"),
	%  the same argument called both: it is the key
	P2 = _{title: "t", groups: [], layers: [],
	       gauges: [_{template: "available(Fork)", value_var: "Fork",
			  key_var: "Fork", label: "free"}]},
	scene_clauses(P2, twod, [instances(Inst)], T2, D2),
	sub_string(T2, _, _, _, "lps_cell(available, fork1,"),
	\+ ( member(diag(warning, scene_free_variable, _, _, _), D2) ),
	%  …but a fluent that never holds of two things at once keeps its value
	P3 = _{title: "t", groups: [], layers: [],
	       gauges: [_{template: "temperature(T)", value_var: "T", label: "temp"}]},
	scene_clauses(P3, twod,
		      [instances(['temperature'/1-inst([temperature(14), temperature(15)], 1)])],
		      T3, _),
	sub_string(T3, _, _, _, "display(temperature(Value)"),
	\+ sub_string(T3, _, _, _, "lps_cell(temperature").

/*  R7c: a plan that nearly says a shape is drawn as the shape it nearly says,
    the way promote_stacks/8 already forgives a tower called a container. Both
    of these came back from a small model on the corpus, and both used to draw
    nothing at all while the summary claimed four things.
*/
t_salvaged_layer :-
	%  a layer whose template names ONE thing: a gauge of what it is doing
	P1 = _{title: "river", groups: [_{id: "north"}, _{id: "south"}],
	       layers: [_{template: "loc(wolf, Where)", group_var: "Where",
			  member_var: "Object", members: [_{id: "wolf"}]}]},
	scene_clauses(P1, twod, [], T1, D1),
	sub_string(T1, _, _, _, "display(loc(wolf, Value)"),
	sub_string(T1, _, _, _, "label:(wolf:Value)"),
	memberchk(diag(info, scene_layer_salvaged, _, _, _), D1),
	\+ memberchk(diag(warning, scene_bad_layer, _, _, _), D1),
	%  a layer whose template is a flag per thing: a lamp each, keyed by the
	%  values the run gave it
	P2 = _{title: "t", groups: [_{id: "here"}], layers: [
		 _{template: "fire(A)", group_var: "A", member_var: "fire"}]},
	scene_clauses(P2, twod,
		      [instances(['fire'/1-inst([fire(kitchen), fire(hall)], 2)])],
		      T2, D2),
	sub_string(T2, _, _, _, "lps_cell(fire, Key, X0, Y0, X1, Y1)"),
	sub_string(T2, _, _, _, "lps_cell(fire, kitchen,"),
	sub_string(T2, _, _, _, "lps_cell(fire, hall,"),
	memberchk(diag(info, scene_layer_salvaged, _, _, _), D2).

/*  R7a/b: what the caller is told was drawn is what the generator ACCEPTED.
    The summary used to count the plan — "2 container(s), 4 thing(s)" over two
    empty boxes — and the coverage check used to read the plan's templates,
    including those of layers it had thrown away.
*/
t_drawn_report :-
	Plan = _{title: "t", groups: [_{id: "here"}],
		 layers: [_{template: "at(X, Y)", group_var: "nope", member_var: "X",
			    members: [_{id: "a"}, _{id: "b"}, _{id: "c"}]}],
		 gauges: [_{template: "alerted", label: "alerted"}]},
	lps_scene:scene_clauses(Plan, twod, [], _, Diags, drawn(Keys, NG, NT)),
	%  the layer was not drawn — its group_var is not in its template — so
	%  neither it nor its three things are claimed
	memberchk(diag(warning, scene_bad_layer, _, _, _), Diags),
	\+ memberchk(at/2, Keys),
	memberchk(alerted/0, Keys),
	%  …and neither is the container it would have put them in: a box
	%  nothing can ever be in is not drawn, and not counted
	memberchk(diag(warning, scene_no_layers_for_groups, _, _, _), Diags),
	NG =:= 0, NT =:= 1.

/*  R8: a lane is for things that take time. `makeLoc(thing, place)` is
    recorded for every thing at every cycle and most of those acts are
    instantaneous — start = end — so the goat's lane was twenty overlapping
    bars with their labels piled into `m m m m moving:wolfge`. An act that
    lasted is a bar; an instant is a tick; a bar narrower than its own label
    goes unlabelled, because a word printed over a sliver is not a label.
*/
t_span_ticks :-
	Plan = _{title: "t", groups: [], layers: [],
		 spans: [_{template: "crossing(To)", member_var: "To",
			   label: "crossing"}]},
	scene_clauses(Plan, twod, [], Text, _),
	%  an act that lasts, labelled…
	once(( sub_string(Text, B1, _, _, "E > S,"), sub_string(Text, B1, 60, _, Bar) )),
	sub_string(Bar, _, _, _, ">="),
	%  …the same, too narrow for the label, with no label at all
	aggregate_all(count, sub_string(Text, _, _, _, "E > S,"), 2),
	once(( sub_string(Text, B2, _, _, "E =:= S"), sub_string(Text, B2, 60, _, Tick) )),
	sub_string(Tick, _, _, _, "+ 3.0"),
	%  and the tick has nothing written on it
	once(( sub_string(Text, B3, _, _, "display(happens(crossing(What), S, E)"),
	       sub_string(Text, B3, _, 0, Rest),
	       sub_string(Rest, B4, _, _, "E =:= S"),
	       sub_string(Rest, 0, B4, _, Before) )),
	aggregate_all(count, sub_string(Before, _, _, _, "label:"), 1),
	%  three dimensions makes the same distinction
	scene_clauses(Plan, threed, [], T3, _),
	sub_string(T3, _, _, _, "E > S, X0 is"),
	sub_string(T3, _, _, _, "E =:= S, X is").

/*  What the assistant is told these libraries contain is read from the
    manifests, so the three catalogues cannot drift from what the renderers
    have. (The other half of that check — that every 3D object listed is also
    built — is in tools/ide_check.cjs, where the builders live.)
*/
t_catalogues :-
	lps_assistant:library_catalogue('/ui/patterns/manifest.json', patterns, Fills),
	sub_string(Fills, _, _, _, "hatch"),
	sub_string(Fills, _, _, _, "bricks"),
	lps_assistant:library_catalogue('/ui/models3d/manifest.json', models, Objects),
	sub_string(Objects, _, _, _, "tree"),
	sub_string(Objects, _, _, _, "truck"),
	\+ sub_string(Fills, _, _, _, "unavailable on this server"),
	\+ sub_string(Objects, _, _, _, "unavailable on this server").

/*  Two defects reported on the Kowalski book's examples. In event_calculus,
    `has(Who, Thing)` puts the book in Mary's or John's keeping and
    `at(Who, Place)` puts them in the library or the cafe: john and mary are
    containers of one layer and things of the other, which the promotion
    heuristic read as a support relation. Both layers then drew nothing (the
    containers were removed, and `lps_slot/4` was never written). The run
    settles it: nobody ever stands on anybody.
*/
t_not_promoted_by_run :-
	Inst = ['has'/2-inst([has(mary, book), has(john, book)], 1),
		'at'/2-inst([at(mary, library), at(john, library), at(john, cafe)], 2)],
	P = _{title: "t",
	      groups: [_{id: "cafe"}, _{id: "library"}, _{id: "mary"}, _{id: "john"}],
	      layers: [_{template: "has(Where, What)", group_var: "Where",
			 member_var: "What", members: [_{id: "book"}]},
		       _{template: "at(What, Where)", group_var: "Where",
			 member_var: "What", members: [_{id: "mary"}, _{id: "john"}]}]},
	scene_clauses(P, twod, [instances(Inst)], T, D),
	\+ memberchk(diag(info, scene_promoted_stack, _, _, _), D),
	\+ sub_string(T, _, _, _, "lps_pile"),
	sub_string(T, _, _, _, "lps_slot(library, mary,"),
	sub_string(T, _, _, _, "lps_slot(mary, book,"),
	%  and without a run, the plan is taken at its word, as before
	scene_clauses(P, twod, [], _, D0),
	memberchk(diag(info, scene_promoted_stack, _, _, _), D0).

/*  fox_crow: the 2D plan made a stack of `has(Where, What)` — the cheese
    standing on the crow — and drew a cheese at the floor with no crow and no
    fox in the picture, while the 3D plan drew them as containers.
*/
t_stack_demoted :-
	Inst = ['has'/2-inst([has(crow, cheese), has(fox, cheese)], 1)],
	P = _{title: "t", groups: [],
	      stacks: [_{template: "has(Where, What)", member_var: "What",
			 support_var: "Where",
			 members: [_{id: "crow"}, _{id: "fox"}, _{id: "cheese"}]}]},
	scene_clauses(P, twod, [instances(Inst)], T, D),
	memberchk(diag(info, scene_demoted_stack, _, _, _), D),
	\+ sub_string(T, _, _, _, "lps_pile"),
	sub_string(T, _, _, _, "lps_slot(crow, cheese,"),
	sub_string(T, _, _, _, "lps_slot(fox, cheese,"),
	\+ sub_string(T, _, _, _, "lps_slot(crow, crow,"),
	scene_clauses(P, threed, [instances(Inst)], T3, _),
	sub_string(T3, _, _, _, "lps_slot3(crow, cheese,").

t_stack_kept :-
	Inst = ['on'/2-inst([on(a, b), on(b, table), on(c, table)], 3)],
	P = _{title: "t", groups: [],
	      stacks: [_{template: "on(Block, Support)", member_var: "Block",
			 support_var: "Support", ground: "table",
			 members: [_{id: "a"}, _{id: "b"}, _{id: "c"}]}]},
	scene_clauses(P, twod, [instances(Inst)], T, D),
	\+ memberchk(diag(info, scene_demoted_stack, _, _, _), D),
	sub_string(T, _, _, _, "lps_pile").


/*  §11 grids. The self-driving cars: `location(Car, X-Y, Heading)` puts a car
    at a coordinate, which no container, gauge or stack can draw — "Animate in
    2D" answered scene_nothing. A grid is measured on the run: here x runs
    1..3 and y 1..2, so with one cell of margin the map is 5 by 4 cells.
*/
grid_inst(['location'/3-inst([location(car1, 1-1, north), location(car1, 1-2, north),
			      location(car2, 3-1, west)], 2)]).

t_grid :-
	grid_inst(Inst),
	P = _{title: "cars", groups: [], layers: [],
	      grids: [_{template: "location(Car, Place, Heading)", member_var: "Car",
			position_var: "Place", label: "streets",
			members: [_{id: "car1", icon: "car"}, _{id: "car2", icon: "car"}]}]},
	scene_clauses(P, twod, [instances(Inst)], T, D, drawn(Keys, 0, 2)),
	\+ memberchk(diag(error, _, _, _, _), D),
	Keys == [location/3],
	sub_string(T, _, _, _, "display(location(What, GX-GY, _), [type:raster"),
	sub_string(T, _, _, _, "lps_grid_1(X, Y, CX, CY) :-"),
	%  5 x 4 cells, three of them roads
	aggregate_all(count, sub_string(T, _, _, _, "fillColor:'#2f3542', strokeColor:'#3a4152'"), 3),
	aggregate_all(count, sub_string(T, _, _, _, "strokeColor:'#232835'"), 17),
	%  the generated clauses are Prolog, and put car1 at (1,2) one cell above (1,1)
	term_string_clauses(T, Cls),
	memberchk((lps_grid_1(A, B, C, E) :- Body), Cls),
	retractall(scene_grid_probe:lps_grid_1(_, _, _, _)),
	assertz(scene_grid_probe:(lps_grid_1(A, B, C, E) :- Body)),
	scene_grid_probe:lps_grid_1(1, 1, CX1, CY1),
	scene_grid_probe:lps_grid_1(1, 2, CX2, CY2),
	CX2 =:= CX1, CY2 > CY1.

t_grid_promoted :-
	grid_inst(Inst),
	P = _{title: "cars", groups: [_{id: "1-1"}, _{id: "3-1"}],
	      layers: [_{template: "location(Car, Place, Heading)", group_var: "Place",
			 member_var: "Car", shape: "circle"}]},
	scene_clauses(P, twod, [instances(Inst)], T, D, drawn([location/3], 0, 2)),
	memberchk(diag(info, scene_layer_to_grid, _, _, _), D),
	sub_string(T, _, _, _, "lps_grid_1("),
	\+ sub_string(T, _, _, _, "lps_slot(").

t_grid_3d :-
	grid_inst(Inst),
	P = _{title: "cars", groups: [], layers: [],
	      grids: [_{template: "location(Car, Place, Heading)", member_var: "Car",
			position_var: "Place"}]},
	scene_clauses(P, threed, [instances(Inst)], _, D),
	memberchk(diag(warning, scene_grid_2d_only, _, _, _), D).

term_string_clauses(Text, Clauses) :-
	setup_call_cleanup(open_string(Text, In), read_clauses(In, Clauses), close(In)).

read_clauses(In, Cs) :-
	read_term(In, T, []),
	( T == end_of_file -> Cs = [] ; Cs = [T|R], read_clauses(In, R) ).

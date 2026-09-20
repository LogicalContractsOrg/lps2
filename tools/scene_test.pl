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
	lps_http:source_terms(Source, Terms, []),
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
test('the libraries the assistant is told about are the ones that exist', t_catalogues).

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

%	The `scenes` operation, which is what the IDE's "split into scenes" asks
%	for: the run as pictures rather than as a canvas to scrub through.
strip(Source, Kind, Reply) :-
	source_run(Source, S),
	register_session(S, Id),
	lps_http:operation("scenes", _{session: Id, kind: Kind}, Reply).

register_session(S, Id) :-
	lps_http:register_session(S, Id).

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

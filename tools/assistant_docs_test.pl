/* assistant_docs_test.pl — the assistant answers questions with the documentation.

   The documentation's search on the server (src/edges/lps_docs_search.pl, kept
   equal to LE2's le_docs_search.pl) and the assistant's use of it: a question
   typed into the assistant gets the sections that may answer it in its prompt,
   a `docs` action searches again, and the links are the viewer's anchors. The
   model is a stub (no key, no network): it asks `docs`, then finishes citing
   a link it was given.

   Usage:
     ./myswipl.sh -q -g "consult('tools/assistant_docs_test.pl')" -g "asdocs:main" -t halt
*/

:- module(asdocs, [main/0]).

:- use_module('../src/edges/lps_http').

main :-
	findall(Name-Result, ( check(Name, Goal), ( catch(Goal, E, (print_message(error, E), fail)) -> Result = ok ; Result = 'FAIL' ) ), Rs),
	forall(member(N-R, Rs), format('~w~t~60|~w~n', [N, R])),
	include([_-R]>>(R == ok), Rs, OK),
	length(Rs, T), length(OK, K),
	format('~n=== assistant and documentation: ~w of ~w ===~n', [K, T]),
	( K =:= T -> true ; halt(1) ).

root(Root) :- lps_assistant:docs_root(Root).

check('a question finds its section, first', (
	root(Root),
	lps_docs_search:docs_search(Root, "how do I write a causal law?", [slug(lps2)], [H|_]),
	get_dict(url, H, U),
	sub_string(U, _, _, _, "#5-causal-laws") )).
check('the anchors are the LPS2 viewer\'s', (
	lps_docs_search:slug(lps2, "3.4 when … then … — causal laws", S),
	S == "34-when--then---causal-laws" )).
check('a greeting finds nothing', (
	lps_assistant:docs_material("hello there", B), B == "" )).
check('a question typed in gets documentation, a toolbar command none', (
	stub_run("How do I observe events in a live session?", Seen1, _),
	sub_string(Seen1, _, _, _, "=== DOCUMENTATION THAT MAY HELP ==="),
	stub_run("__animate_2d__", Seen2, _),
	\+ sub_string(Seen2, _, _, _, "=== DOCUMENTATION THAT MAY HELP ===") )).
check('the docs action answers, and finish cites a link', (
	stub_run("What is a causal law?", Seen, Expl),
	sub_string(Seen, _, _, _, "Sections of the documentation for \"causal laws\""),
	sub_string(Expl, _, _, _, "](/docs/user/") )).

%	A job run in this thread with the stub for a model. Seen: every message
%	the model was sent; Expl: the answer.
stub_run(Command, Seen, Expl) :-
	nb_setval(asdocs_seen, ""),
	Id = 'asdocs-job',
	lps_assistant:set_job(Id, _{status: running, output: [], explanation: "",
				    new_content: null, new_companion: null,
				    error: null, interrupt: false}),
	setup_call_cleanup(
	    wrap_predicate(lps_llm:llm_request(_M, Msgs, Reply, _O), asdocs, _W, stub_reply(Msgs, Reply)),
	    catch(lps_assistant:run_job_(Id, _{command: Command, content: "fluents lit.\n",
					       name: "t.lps", model: "gpt-4o",
					       api_keys: _{openai: "stub-key"}}), _, true),
	    unwrap_predicate(lps_llm:llm_request/4, asdocs)),
	nb_getval(asdocs_seen, Seen),
	(   lps_assistant:job_state(Id, S), get_dict(explanation, S, Expl) -> true ; Expl = "" ).

stub_reply(Msgs, Reply) :-
	with_output_to(string(All), forall(member(M, Msgs), ( M = role(_, C) -> write(C) ; write(M) ))),
	nb_setval(asdocs_seen, All),
	last(Msgs, role(_, Last)),
	(   Msgs = [_, role(user, Command)|_],
	    sub_string(Command, 0, _, _, "Give this program a")   % a toolbar command
	->  Reply = "{\"action\":\"finish\",\"explanation\":\"Nothing to animate.\"}"
	;   sub_string(Last, B, _, _, "(/docs/user/")
	->  sub_string(Last, B, _, 0, After),
	    sub_string(After, E, _, _, ")"), !,
	    sub_string(After, 1, _, _, _),
	    E1 is E - 1, sub_string(After, 1, E1, _, Url),
	    format(string(Reply), "{\"action\":\"finish\",\"explanation\":\"See [causal laws](~w).\"}", [Url])
	;   Reply = "{\"action\":\"docs\",\"query\":\"causal laws\"}"
	).

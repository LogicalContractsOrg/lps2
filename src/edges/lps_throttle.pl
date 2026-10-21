/*  lps_throttle.pl — the limits of the public tools of /mcp, for LPS2.

    The tools of `/mcp` answer anyone, without signing in. LE2's
    `le_throttle.pl` keeps one client from taking the server for itself: who
    asks (a key, a sign-in, or the address), the budget of each client, the
    size of the texts a call sends, the calls that run at once, and their time
    (LE2's docs/project/plans/MCPThrottling.md). This module loads that file
    and gives LPS2's MCP server (lps_mcp.pl) four predicates.

    Which copy is loaded matters. LE2's modules have the same names in every
    checkout, and one image cannot hold two copies of a module (lps_le.pl,
    lps_le_load/2). So the copy is the one beside the LE2 that LPS2 itself
    loads in-process (`LPS_LE2_LIB`), and otherwise the one vendored in
    vendor/le2. Without either, nothing is limited: every call runs, as
    before.

    Keys are lpsPlus's (accounts/lc_accounts.pl, loaded by lps_plus.pl): it
    answers le_throttle's hook, and a key's licences apply to the call
    (lps_plus_set_visitor/2).
*/

:- module(lps_throttle, [
	lps_throttle_load/0,
	lps_throttle_identity/2,	% +Request, -Identity
	lps_throttle_admit/4,		% +Identity, +Tool, +Args, -Verdict
	lps_throttle_admit_cost/3,	% +Identity, +Cost, -Verdict
	lps_throttle_own_key_note/1,	% -Sentence
	lps_throttle_run/3,		% +Identity, :Goal, -Outcome
	lps_throttle_session/1		% -SessionId
	]).

:- use_module(lps_le).
:- use_module('../syntax/lps_plus').

:- meta_predicate lps_throttle_run(+, 0, -).

:- dynamic throttle_file/1.

%!	lps_throttle_load is det.
%
%	Load le_throttle.pl, once: called when the server starts.
lps_throttle_load :-
	throttle_file(_), !.
lps_throttle_load :-
	(   throttle_source(File)
	->  catch(( use_module(File), assertz(throttle_file(File)) ), E,
		  print_message(warning, E))
	;   print_message(warning,
		format('No le_throttle.pl beside LE2 or in vendor/le2: the tools of /mcp are not limited.', []))
	).

throttle_source(File) :-
	(   lps_le_available(lib(Dir))
	->  true
	;   lps_vendor_le2(Dir)
	),
	atomic_list_concat([Dir, '/le_throttle.pl'], File),
	exists_file(File).

lps_vendor_le2(Dir) :-
	module_property(lps_throttle, file(F)),
	file_directory_name(F, Edges), file_directory_name(Edges, Src),
	file_directory_name(Src, Root),
	atomic_list_concat([Root, '/vendor/le2'], Dir),
	exists_directory(Dir).

loaded :- throttle_file(_).

%!	lps_throttle_identity(+Request, -Identity) is det.
%
%	Who asks; a key's licences apply to this request. Without le_throttle,
%	every client is `local`, which nothing limits.
lps_throttle_identity(Request, Identity) :-
	(   loaded
	->  le_throttle:throttle_identity(Request, Identity),
	    (   get_dict(caps, Identity, Caps), is_list(Caps)
	    ->  ( get_dict(email, Identity, Email) -> true ; Email = anonymous ),
		lps_plus_set_visitor(Email, Caps)
	    ;   true
	    )
	;   Identity = _{level: local, id: local}
	).

%!	lps_throttle_admit(+Identity, +Tool, +Args, -Verdict) is det.
%
%	A look-up (the lists, a world's status, closing it) costs one; a
%	tool that compiles or runs a program, three. The text of `source`
%	counts against the size limit.
lps_throttle_admit(Identity, Tool, Args, Verdict) :-
	(   loaded
	->  ( memberchk(Tool, [list_programs, list_live, list_worlds, world_status, close_world]) -> Cost = 1 ; Cost = 3 ),
	    (   is_dict(Args), get_dict(source, Args, S), ( string(S) ; atom(S) )
	    ->  string_length(S, L), Ls = [L]
	    ;   Ls = []
	    ),
	    le_throttle:throttle_admit(Identity, Cost, Ls, Verdict)
	;   Verdict = allow
	).

%!	lps_throttle_admit_cost(+Identity, +Cost, -Verdict) is det.
%
%	A call of a known cost, with no text to measure: an assistant's
%	request that the server pays for (lps_http.pl, llm_budget/3).
lps_throttle_admit_cost(Identity, Cost, Verdict) :-
	(   loaded
	->  le_throttle:throttle_admit(Identity, Cost, [], Verdict)
	;   Verdict = allow
	).

%!	lps_throttle_own_key_note(-Sentence) is det.
%
%	The sentence added to an assistant's refusal: with the user's own key
%	for the model's provider, there is no limit.
lps_throttle_own_key_note(S) :-
	(   loaded, catch(le_i18n:le_msg(throttle_own_llm_key, [], M), _, fail)
	->  atom_string(M, S)
	;   S = ""
	).

%!	lps_throttle_run(+Identity, :Goal, -Outcome) is det.
lps_throttle_run(Identity, Goal, Outcome) :-
	(   loaded
	->  le_throttle:throttle_run(Identity, Goal, Outcome)
	;   catch(( once(Goal) -> Outcome = done ; Outcome = failed ), E, Outcome = error(E))
	).

%!	lps_throttle_session(-SessionId) is semidet.
lps_throttle_session(Id) :-
	loaded,
	le_throttle:throttle_new_session(Id).

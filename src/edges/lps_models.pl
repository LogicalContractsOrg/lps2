/* lps_models.pl — which models a provider actually has, asked at the source.
 *
 * `lps_llm.pl` carries a hand-maintained table of model names, copied from
 * LE2 and kept in sync by hand. That table is fine as a fallback and wrong as
 * an answer: a model listed there may have been retired last week, and one
 * released yesterday is not in it. The IDE's model picker was therefore a list
 * of guesses, and the only way to fix a stale entry was to edit Prolog.
 *
 * Every provider we support publishes its catalogue over HTTP. So: ask them,
 * once, at server start (in a thread, because a provider being slow must not
 * make `./lps ide` slow to come up), cache the answer, and let the client force
 * a re-read. The static table remains the fallback for a provider that is
 * unreachable, so an offline deployment still offers something.
 *
 * This is an edge: it opens sockets and reads the clock. Nothing in src/core/
 * knows any of it exists.
 */

:- module(lps_models, [
	models_start/0,           % kick off discovery in the background
	models_refresh/1,         % +Keys (dict), re-read now, synchronously
	models_available/2,       % +Keys, -List of _{name, provider, source}
	model_window/2,           % +Name, -Context window in tokens (semidet)
	model_max_output/2        % +Name, -Completion limit in tokens (semidet)
	]).

:- use_module(library(http/http_open)).
:- use_module(library(http/json)).
:- use_module(library(http/http_json)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(lps_llm).

:- dynamic discovered/3.        % Provider, Name, Stamp
:- dynamic discovery_done/1.    % Provider
/*  How much a model can be told at once.
 *
 *  Groq's catalogue reports `context_window` and `max_completion_tokens` per
 *  model, and most of what it hosts is an 8,192-token model. Discarding those
 *  two numbers meant the picker offered a model that could not hold the
 *  assistant's own prompt, and the only way to find out was to choose it and
 *  read the provider's refusal. Providers that do not report them are simply
 *  not recorded, and everything downstream treats "not known" as "no opinion". */
:- dynamic model_limit/3.       % Provider, Name, limits(Context, MaxOut)

%!	provider_catalogue(+Provider, -URL, -Style) is semidet.
%
%	Style is `openai` (a `data` array of `{id}`), `anthropic` (the same, but
%	authenticated differently) or `gemini` (`models` of `{name}`).
provider_catalogue(openai,    'https://api.openai.com/v1/models',            openai).
provider_catalogue(groq,      'https://api.groq.com/openai/v1/models',       openai).
provider_catalogue(together,  'https://api.together.xyz/v1/models',          openai).
provider_catalogue(anthropic, 'https://api.anthropic.com/v1/models',         anthropic).
provider_catalogue(gemini,    'https://generativelanguage.googleapis.com/v1beta/models', gemini).

%!	models_start is det.
%
%	Fire discovery for every provider whose key is in the *server's*
%	environment. Browser-supplied keys are not touched here — they arrive per
%	request, and a server that went off and probed a provider with a key a
%	page handed it would be doing something the user did not ask for.
models_start :-
	catch(thread_create(models_probe_all, _, [detached(true)]), _, true).

models_probe_all :-
	forall(( provider_catalogue(P, _, _), catch(api_key(P, _), _, fail) ),
	       catch(probe(P, _{}), _, true)).

%!	models_refresh(+Keys) is det.
models_refresh(Keys) :-
	forall(( provider_catalogue(P, _, _), have_key_for(P, Keys, _) ),
	       catch(probe(P, Keys), _, true)).

have_key_for(P, _Keys, K) :- catch(api_key(P, K), _, fail), !.
have_key_for(P, Keys, K) :-
	%  A JSON dict's keys are *atoms*; `get_dict/3` with a string key is a
	%  type error, not a failure, and it escaped the catch around probe/2 and
	%  took the whole refresh with it — which is why the picker kept showing
	%  the built-in table however many times it was re-read.
	is_dict(Keys), get_dict(P, Keys, K0), K0 \== "", K0 \== null, !,
	( atom(K0) -> K = K0 ; atom_string(K, K0) ).

probe(Provider, Keys) :-
	provider_catalogue(Provider, URL0, Style),
	have_key_for(Provider, Keys, Key),
	auth(Style, Key, URL0, URL, Headers),
	setup_call_cleanup(
	    http_open(URL, In, [ request_header('Accept'='application/json')
			       | Headers ]),
	    json_read_dict(In, Reply),
	    close(In)),
	catalogue_names(Style, Reply, Names),
	get_time(Now),
	retractall(discovered(Provider, _, _)),
	forall(member(N, Names), assertz(discovered(Provider, N, Now))),
	retractall(model_limit(Provider, _, _)),
	forall(catalogue_limit(Style, Reply, N2, Ctx, Out),
	       assertz(model_limit(Provider, N2, limits(Ctx, Out)))),
	%  A name nobody can route is worse than no name: register each one with
	%  lps_llm so `llm_request/4` knows its provider and base URL. Without
	%  this the picker offers a model and choosing it reports "no API key for
	%  openai", because the router's fallback guesses openai for anything it
	%  has never heard of.
	provider_base(Provider, Base),
	forall(member(N, Names),
	       ( atom_string(NA, N),
		 catch(llm_register_model(NA, Provider, NA, Base), _, true) )),
	retractall(discovery_done(Provider)),
	assertz(discovery_done(Provider)).

%	The chat endpoint's base, which is the catalogue URL without `/models`.
provider_base(Provider, Base) :-
	provider_catalogue(Provider, URL, _),
	atom_concat(Base, '/models', URL), !.
provider_base(gemini, 'https://generativelanguage.googleapis.com/v1beta/openai').

auth(anthropic, Key, U, U, [ request_header('x-api-key'=Key),
			     request_header('anthropic-version'='2023-06-01') ]).
auth(gemini, Key, U0, U, []) :- atomic_list_concat([U0, '?key=', Key], U).
auth(openai, Key, U, U, [request_header('Authorization'=Auth)]) :-
	atomic_list_concat(['Bearer ', Key], Auth).

catalogue_names(gemini, Reply, Names) :- !,
	(   get_dict(models, Reply, Ms), is_list(Ms)
	->  findall(N, ( member(M, Ms), get_dict(name, M, Full),
			 strip_prefix("models/", Full, N) ), Names)
	;   Names = []
	).
catalogue_names(_, Reply, Names) :-
	(   get_dict(data, Reply, Ms), is_list(Ms)
	->  findall(N, ( member(M, Ms), get_dict(id, M, N) ), Names)
	;   Names = []
	).

strip_prefix(P, S, Out) :-
	(   string_concat(P, Rest, S) -> Out = Rest ; Out = S ).

%!	catalogue_limit(+Style, +Reply, -Name, -Context, -MaxOut) is nondet.
%
%	The per-model limits, where the provider reports them. Groq does, in the
%	OpenAI-shaped listing; OpenAI and Anthropic do not, and their models are
%	then simply unconstrained as far as this file is concerned.
catalogue_limit(gemini, Reply, Name, Ctx, Out) :- !,
	get_dict(models, Reply, Ms), is_list(Ms), member(M, Ms),
	get_dict(name, M, Full), strip_prefix("models/", Full, Name),
	( get_dict(inputTokenLimit, M, Ctx) -> true ; fail ),
	( get_dict(outputTokenLimit, M, Out) -> true ; Out = 0 ).
catalogue_limit(_, Reply, Name, Ctx, Out) :-
	get_dict(data, Reply, Ms), is_list(Ms), member(M, Ms),
	get_dict(id, M, Name),
	( get_dict(context_window, M, Ctx) -> true ; fail ),
	( get_dict(max_completion_tokens, M, Out0), integer(Out0) -> Out = Out0 ; Out = 0 ).

%!	model_window(+Name, -Tokens) is semidet.
%
%	How much this model can be told at once, if anybody said. Fails when the
%	provider does not report it, which callers must read as "no opinion"
%	rather than as "zero".
model_window(Name, Tokens) :-
	( atom(Name) -> atom_string(Name, S) ; S = Name ),
	model_limit(_, S, limits(Tokens, _)),
	integer(Tokens), Tokens > 0, !.

%!	model_max_output(+Name, -Tokens) is semidet.
model_max_output(Name, Tokens) :-
	( atom(Name) -> atom_string(Name, S) ; S = Name ),
	model_limit(_, S, limits(_, Tokens)),
	integer(Tokens), Tokens > 0, !.

/*  A provider's catalogue is everything it hosts, not everything you can hold
    a conversation with: Groq's includes Whisper, Orpheus and two prompt-guard
    classifiers, and offering them in a picker labelled "model" would be a list
    that mostly errors when chosen. There is no capability field in the plain
    `/models` listing to key off, so this is a name filter — deliberately a
    small one, because excluding a real model is the worse mistake. */
chat_model(Name) :-
	string_lower(Name, L),
	\+ ( member(Bad, ["whisper", "tts", "embed", "guard", "orpheus",
			  "moderation", "rerank", "playai", "distil-whisper"]),
	     sub_string(L, _, _, _, Bad) ).

%!	models_available(+Keys, -Models) is det.
%
%	What to offer. Discovered names first, then anything in the static table
%	for a provider we could not reach — so the picker is right when the
%	network works and non-empty when it does not.
models_available(Keys, Models) :-
	findall(_{name: N, provider: P, source: "provider", curated: C, window: W},
		( discovered(Prov, N0, _), atom_string(Prov, P),
		  ( string(N0) -> N = N0 ; atom_string(N0, N) ),
		  chat_model(N),
		  have_key_for(Prov, Keys, _),
		  curated(N, C),
		  ( model_window(N, W) -> true ; W = 0 ) ),
		Live),
	findall(_{name: N, provider: P, source: "builtin", curated: true, window: 0},
		( llm_list_models(Rows), member(row(Name, Prov, _), Rows),
		  have_key_for(Prov, Keys, _),
		  \+ discovery_done(Prov),
		  atom_string(Name, N), atom_string(Prov, P) ),
		Static),
	append(Live, Static, All),
	sort(name, @=<, All, Models).

/*  `curated` marks a discovered model that is *also* in lps_llm's hand-written
    table. The picker stays in name order, because a list that reorders itself
    is a list you cannot find anything in — but the *default* has to come from
    somewhere better than "alphabetically first", which after discovery was
    `allam-2-7b`: a real model, with a 4096-token limit that the assistant's own
    request exceeds. The hand-written table is the list somebody chose. */
curated(Name, Curated) :-
	atom_string(A, Name),
	(   llm_model_entry_static(A) -> Curated = true ; Curated = (false) ).

%	lps_llm's *compiled* clauses, not `llm_list_models/1` — that one now also
%	reports what discovery registered, so asking it whether a name is in the
%	hand-written table says yes to everything.
llm_model_entry_static(A) :-
	catch(lps_llm:llm_model_entry(A, _, _, _), _, fail).

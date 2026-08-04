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
	models_available/2        % +Keys, -List of _{name, provider, source}
	]).

:- use_module(library(http/http_open)).
:- use_module(library(http/json)).
:- use_module(library(http/http_json)).
:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(lps_llm).

:- dynamic discovered/3.        % Provider, Name, Stamp
:- dynamic discovery_done/1.    % Provider

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
	is_dict(Keys), atom_string(P, PS), get_dict(PS, Keys, K0), K0 \== "", !,
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
	retractall(discovery_done(Provider)),
	assertz(discovery_done(Provider)).

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

%!	models_available(+Keys, -Models) is det.
%
%	What to offer. Discovered names first, then anything in the static table
%	for a provider we could not reach — so the picker is right when the
%	network works and non-empty when it does not.
models_available(Keys, Models) :-
	findall(_{name: N, provider: P, source: "provider"},
		( discovered(Prov, N0, _), atom_string(Prov, P),
		  ( string(N0) -> N = N0 ; atom_string(N0, N) ),
		  have_key_for(Prov, Keys, _) ),
		Live),
	findall(_{name: N, provider: P, source: "builtin"},
		( llm_list_models(Rows), member(row(Name, Prov, _), Rows),
		  have_key_for(Prov, Keys, _),
		  \+ discovery_done(Prov),
		  atom_string(Name, N), atom_string(Prov, P) ),
		Static),
	append(Live, Static, All),
	sort(name, @=<, All, Models).

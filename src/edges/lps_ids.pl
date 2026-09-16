/* lps_ids.pl — ids that belong to the process that minted them.
 *
 * Every handle this server hands out — a compiled program, a run session, an
 * assistant job, a live session — names a term held in *this* process's memory,
 * and every one of them is minted from a counter starting at zero. Two
 * processes of the same image therefore mint the same names: both call their
 * first session `s1`.
 *
 * That was only ever a bug in the plural, and it arrived by default. A
 * `fly deploy` gives an app two machines unless told otherwise; the proxy sent
 * a `run` to one and the `scene` that followed to the other, and `s1` there was
 * either absent — `lps_no_such_session(s1)`, which is what the user saw — or,
 * quite as likely and far worse, somebody else's session, answered from
 * silently. The deployment is now pinned to one machine (docs/dev/deploy.md),
 * because the server is one stateful process by design and nothing about it is
 * horizontally scalable today.
 *
 * This is the belt to that's braces: a per-process tag on every id, so that a
 * handle which finds its way to the wrong process cannot be mistaken for a
 * local one. The failure that survives is the honest one — "no such session" —
 * and never the quiet wrong answer.
 *
 * The tag is not a secret and does not try to be one: it is unguessable enough
 * that ids do not collide, not enough to authorise anything. Authorisation is
 * `LPS_TOKEN`'s job.
 */

:- module(lps_ids, [
	tagged_id/2,           % +Base, -Id
	server_nonce/1         % -Atom
	]).

:- use_module(library(random)).

:- dynamic nonce_cache/1.

%!	server_nonce(-Nonce) is det.
%
%	Six hex digits, fixed for the lifetime of this process. The pid is
%	mixed in because two processes started in the same instant on the same
%	host are exactly the case a bare random seed is worst at.
server_nonce(Nonce) :-
	nonce_cache(Nonce), !.
server_nonce(Nonce) :-
	with_mutex(lps_ids, ensure_nonce(Nonce)).

ensure_nonce(Nonce) :-
	nonce_cache(Nonce), !.
ensure_nonce(Nonce) :-
	current_prolog_flag(pid, Pid),
	random_between(0, 0xffffff, R),
	N is (Pid * 7919 + R) /\ 0xffffff,
	format(atom(Nonce), '~|~`0t~16r~6|', [N]),
	assertz(nonce_cache(Nonce)).

%!	tagged_id(+Base, -Id) is det.
%
%	`s3` becomes `s3-1b6257`. Clients treat these as opaque — nothing in
%	the IDE or the API parses an id — so the shape is free to say what it
%	needs to.
%	The counter each caller bumps to make `Base` is its own, and each
%	guards it with its own mutex: `retract(c(N)), assertz(c(N1))` run by
%	two HTTP workers at once loses one of them — the second retract finds
%	no clause and the whole registration fails — which is a rarer bug than
%	the one above but the same kind, and it costs nothing to close both at
%	once.
tagged_id(Base, Id) :-
	server_nonce(Nonce),
	atomic_list_concat([Base, -, Nonce], Id).

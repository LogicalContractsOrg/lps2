/* lps_builtins.pl — the engine predicates an LPS program may call.

   A program can ask the engine about itself. `forTesting/meta.pl` does exactly
   that:

	uberFuent(F) at T if holds(F,T), not system_fluent(F).

   — an intensional fluent defined over an arbitrary subset of the state,
   filtered by an engine predicate. Upstream makes this work by accident of
   layout: `callprolog/1` runs built-in goals inside the `interpreter` module,
   where `system_fluent/1` and friends are defined, so the `not/1` meta-call
   resolves its argument there.

   Here the same predicates live in one small module, and p_call/2 falls back
   to it when the program's own module leaves a goal undefined. The difference
   from upstream is deliberate and is an improvement: a program's *own*
   predicates resolve in the program's module first, so `not myPredicate(X)`
   works here and raises an existence error upstream.

   Everything is answered against the session's current program, which the
   store holds.
*/

:- module(lps_builtins, [
	system_fluent/1,
	system_action/1,
	intensional/1,
	macroaction/1,
	action_/1,
	event_/1,
	fluent_/1,
	current_time/1,
	real_time_beginning/1,
	state/1,
	next_state/1,
	happens/3,
	uassert/1,
	uasserta/1,
	uassertz/1,
	uretract/1,
	uretractall/1
	]).

:- use_module(library(lists)).
:- use_module(library(apply)).
:- use_module(lps_store).
:- use_module(lps_program).
:- use_module(lps_time).

%!	system_fluent(?F) is nondet.
%
%	The fluents the engine maintains itself. They live in the state, so a
%	program that walks the state can see them, and this is how it tells
%	them apart from its own.
system_fluent(real_time(_)).
system_fluent(lps_user(_)).
system_fluent(lps_user(_, _)).

system_action(A) :- st_program(P), p_system_action(P, A).
intensional(F)   :- st_program(P), p_intensional(P, F).
macroaction(E)   :- st_program(P), p_macroaction(P, E).
action_(A)       :- st_program(P), p_action(P, A).
event_(E)        :- st_program(P), p_event(P, E).
fluent_(F)       :- st_program(P), p_fluent(P, F).

		 /*******************************
		 *	  engine state		*
		 *******************************/

/* Upstream keeps these in the `db` module alongside the program's own
   clauses, so a program can simply call them — and one does:

	new_lustrum(N) :- current_time(T), 0 is T mod 5, N is T/5.

   wired in as a `prolog_events` poll. Read-only access to the cycle counter
   and the state is a legitimate thing for a program to want; writing to them
   is not, and is not offered.
*/

current_time(T) :- st_now(T).

real_time_beginning(B) :- st_program(P), lps_time:clock_of(P, clock(B, _)).

state(F) :- st_state(F).

next_state(F) :- st_next_state(F).

happens(E, T1, T2) :- st_happens(E, T1, T2).

		 /*******************************
		 *   runtime clause editing	*
		 *******************************/

/* Upstream exposes these so a program can edit its own timeless predicates
   while it runs. They are the one place a program may mutate the *program*
   rather than the state, and they are deliberately confined to its own module.
*/

uassert(X)     :- prog_mod(M), assert(M:X).
uasserta(X)    :- prog_mod(M), asserta(M:X).
uassertz(X)    :- prog_mod(M), assertz(M:X).
uretract(X)    :- prog_mod(M), retract(M:X).
uretractall(X) :- prog_mod(M), retractall(M:X).

prog_mod(M) :- st_program(P), prog_module(P, M).

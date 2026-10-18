/* lps_diag.pl — the structured diagnostic model (§I.2.5).

   Compile-time and run-time problems are *terms*, never printed text:

	diag(Severity, Code, Position, Message, Fixes)

   Severity : error | warning | info
   Code     : an atom naming the problem class, stable across releases, so
	      tools can switch on it (`undeclared_fluent`, not a sentence)
   Position : src(File, Line, Col, SyntaxKind)  |  unknown
   Message  : a human-readable atom, already formatted
   Fixes    : list of fix(Title, Edits) quick-fixes, [] when none

   Rendering to text is an *edge* concern (see src/edges/lps_cli.pl); the core
   only produces and collects these.
*/

:- module(lps_diag, [
	diag/5,                  % +Severity, +Code, +Position, +Message, -Diag
	diag_severity/2,         % +Diag, -Severity
	diag_code/2,             % +Diag, -Code
	diag_position/2,         % +Diag, -Position
	diag_message/2,          % +Diag, -Message
	diag_fixes/2,            % +Diag, -Fixes
	diags_errors/2,          % +Diags, -Errors
	diags_ok/1,              % +Diags        — no errors present
	format_diag/2,           % +Diag, -Atom  — one-line rendering
	src_unknown/1,           % -Position
	interrupt/1,             % +Exception   — one no catch-all may keep
	catch_or_fail/1          % :Goal        — catch(Goal, _, fail), interrupts excepted
	]).

:- use_module(library(lists)).

:- meta_predicate catch_or_fail(0).

%!	interrupt(+Exception) is semidet.
%
%	An exception that stops a computation from *outside* it: a time limit
%	run out, an abort. It is not about the program, so no `catch(G, _, fail)`
%	in the core may turn it into a failure. One that did kept a request
%	running after its time was up: the planner calls the program's Prolog
%	through a catch-all, the time limit's exception was taken for the goal
%	failing, and the search went on — for five minutes, on a server with
%	one processor (Sentry, 2026-10-18, `session_new`).
interrupt(E) :- var(E), !, fail.
interrupt(time_limit_exceeded).
interrupt(time_limit_exceeded(_)).
interrupt('$aborted').
interrupt(unwind(_)).

%!	catch_or_fail(:Goal) is nondet.
%
%	`catch(Goal, _, fail)` — an error in Goal is Goal failing — except that
%	an interrupt/1 passes through.
catch_or_fail(Goal) :-
	catch(Goal, E, ( interrupt(E) -> throw(E) ; fail )).

%!	diag(+Severity, +Code, +Position, +Message, -Diag) is det.
diag(Severity, Code, Position, Message, diag(Severity, Code, Position, Message, [])) :-
	must_be_severity(Severity).

must_be_severity(S) :-
	(   memberchk(S, [error, warning, info])
	->  true
	;   throw(error(domain_error(lps_diag_severity, S), _))
	).

diag_severity(diag(S,_,_,_,_), S).
diag_code(diag(_,C,_,_,_), C).
diag_position(diag(_,_,P,_,_), P).
diag_message(diag(_,_,_,M,_), M).
diag_fixes(diag(_,_,_,_,F), F).

src_unknown(unknown).

diags_errors(Diags, Errors) :-
	include([D]>>diag_severity(D, error), Diags, Errors).

%!	diags_ok(+Diags) is semidet.
diags_ok(Diags) :-
	\+ ( member(D, Diags), diag_severity(D, error) ).

%!	format_diag(+Diag, -Atom) is det.
format_diag(diag(Severity, Code, Position, Message, _), Atom) :-
	format_position(Position, Pos),
	format(atom(Atom), '~w: ~w~w: ~w', [Severity, Code, Pos, Message]).

format_position(unknown, '') :- !.
format_position(src(File, Line, _, _), Atom) :- !,
	format(atom(Atom), ' (~w:~w)', [File, Line]).
format_position(P, Atom) :-
	format(atom(Atom), ' (~w)', [P]).

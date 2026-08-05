/* lps_sandbox.pl — what a program is allowed to call.

   This is about **the Prolog in a user's program**, not about the engine: the
   check is applied to the predicates a program defines, and the interpreter's
   own modules are not its business.

   An LPS rule body may contain ordinary Prolog, which is the language and not
   a hole in it: `lamp_at(X,N) :- N0 is X // 70, ...` is how a program does
   arithmetic. But "ordinary Prolog" includes `shell/1`, `open/3` and
   `process_create/3`, so a server that compiles and runs a program somebody
   sent it is, without this, an open Prolog interpreter — which is why
   `/lpsapi` has needed a token to be deployable at all.

   The check is SWI's own: `library(sandbox)`'s `safe_goal/1`, the same
   mechanism SWISH exposes to the public internet. It permits what LPS
   programs actually do — arithmetic, `between/3`, `format/2`, `findall/3`,
   `assert`/`retract`, sorting, atom and number conversion — and refuses the
   ones that reach the machine.

   ## Why it runs at compile time and not at every call

   `safe_goal/1` on a user-defined goal is ~230 µs, because it follows the
   call graph into that predicate's clauses. On the engine's hottest path
   (`p_call/2`, thousands of calls per cycle) that is not a policy, it is a
   different program. But following the call graph is also what makes checking
   *once* sufficient: asking it about every predicate the program defines
   checks every goal reachable from any of them, transitively.

   A goal built at run time — `G =.. [shell, Cmd], call(G)` — is not reachable
   statically, and this is where the conservatism earns its place: `safe_goal/1`
   refuses a meta-call it cannot resolve, so a program containing one is
   refused *at compile time*, with the offending goal named. That is the same
   trade SWISH makes: a program that constructs its goals cannot run in a
   sandbox, and is told so rather than half-running.

   ## What it does not do

   It is not a resource limit. A sandboxed program can still loop for ever
   inside one cycle, and `maxTime` bounds cycles rather than the Prolog inside
   them. A public deployment still wants a token, or a proxy that limits CPU,
   if the concern is somebody using the machine rather than owning it.
*/

:- module(lps_sandbox, [
	sandbox_check/2,          % +Program, -Diags
	sandbox_enabled/2         % +Options, -Bool
	]).

:- use_module(library(sandbox)).
:- use_module(library(lists)).
:- use_module('../core/lps_diag').
:- use_module('../core/lps_program').

/*  Two additions to SWI's policy, both about *output*.

    `library(sandbox)` refuses `write/1` and its family, because in general
    they take a stream and a stream is a capability. Here they cannot: a
    program has no way to obtain one — `open/3`, `process_create/3` and the
    rest are refused — so the only stream `write/1` can reach is the current
    output, which for a server is its own log. LPS1 programs print: nineteen
    of the corpus programs would be refused for `write/1` alone, and refusing
    a program for printing would make the sandbox look arbitrary rather than
    protective.

    The stream-taking arities (`write/2`, `nl/1`) are deliberately *not*
    declared: they are harmless only because nothing can produce a stream, and
    that is an argument about the rest of the policy rather than about them. */
:- multifile sandbox:safe_primitive/1.
sandbox:safe_primitive(system:write(_)).
sandbox:safe_primitive(system:writeln(_)).
sandbox:safe_primitive(system:print(_)).
sandbox:safe_primitive(system:write_canonical(_)).
sandbox:safe_primitive(system:write_term(_, _)).
sandbox:safe_primitive(system:nl).
sandbox:safe_primitive(system:tab(_)).

%!	sandbox_enabled(+Options, -Bool) is det.
%
%	Whether to check. The default differs by *door*, which is the whole of
%	the policy:
%
%	  - the HTTP endpoint compiles programs from strangers, so it checks
%	    unless `LPS_SANDBOX=0` says the deployment is trusted;
%	  - the CLI runs your own file on your own machine, and the conformance
%	    corpus is full of programs written before any of this existed, so it
%	    does not check unless asked (`--sandbox`, or `LPS_SANDBOX=1`).
%
%	Either way it is explicit: `sandbox(true)` or `sandbox(false)` in Options
%	wins over both.
sandbox_enabled(Options, Bool) :-
	(   memberchk(sandbox(B), Options)
	->  ( B == true -> Bool = true ; Bool = false )
	;   memberchk(default(server), Options)
	->  ( getenv('LPS_SANDBOX', '0') -> Bool = false ; Bool = true )
	;   ( getenv('LPS_SANDBOX', V), V \== '0', V \== '' -> Bool = true ; Bool = false )
	).

%!	sandbox_check(+Program, -Diags) is det.
%
%	One diagnostic per predicate the sandbox will not vouch for, naming the
%	goal it objected to and, where the program's provenance knows it, the
%	line it is on. Empty means every goal reachable from this program's own
%	predicates is safe.
sandbox_check(Program, Diags) :-
	prog_module(Program, Module),
	findall(D, unsafe_predicate(Program, Module, D), Diags0),
	sort(Diags0, Diags).

unsafe_predicate(Program, Module, Diag) :-
	program_defined(Module, Name/Arity),
	functor(Head, Name, Arity),
	\+ p_program_predicate(Head),
	catch(( safe_goal(Module:Head) -> fail ; Why = 'the sandbox could not prove it safe' ),
	      E,
	      ( unsafe_error(E) -> why(E, Why) ; fail )),
	source_of(Program, Head, Src),
	format(atom(M),
	       'this program calls Prolog that a sandboxed server will not run: ~w. \c
		~w is refused. Set LPS_SANDBOX=0 on a server you trust, or run it \c
		from the command line, where the sandbox is off by default.',
	       [Why, Name/Arity]),
	diag(error, sandbox_unsafe, Src, M, Diag).

/*  Which of `safe_goal/1`'s exceptions mean *unsafe*.

    Not all of them do. It follows the call graph, and a call to a predicate
    that does not exist stops it with an existence error — which is a fact
    about the program (it will throw when it gets there, its own business) and
    not about safety: an undefined predicate cannot do anything at all. LPS
    programs are full of these, because an event or an action is declared and
    then called without ever being *defined* as a Prolog predicate. Reporting
    them would have refused two corpus programs for the crime of having a
    declaration.

    The escape this would open if the predicate could later appear — asserting
    it — is closed elsewhere: SWI's sandbox refuses `assertz/1` of any clause
    with a body, safe or not, and `use_module` is refused separately. */
unsafe_error(error(existence_error(procedure, _), _)) :- !, fail.
unsafe_error(_).

%	`permission_error(call, sandboxed, Goal)` is what safe_goal/1 raises, and
%	the Goal in it is the answer to "which line do I look at".
why(error(permission_error(call, sandboxed, G), _), Why) :- !,
	format(atom(Why), '~q is not allowed', [G]).
why(error(instantiation_error, _), Why) :- !,
	Why = 'it builds a goal at run time, and an unbound goal cannot be checked'.
why(E, Why) :- format(atom(Why), '~q', [E]).

%	Every predicate this program defines, whatever it is for. Asking about
%	each of them covers every goal any of them can reach.
program_defined(Module, Name/Arity) :-
	current_predicate(Module:Name/Arity),
	functor(H, Name, Arity),
	\+ predicate_property(Module:H, imported_from(_)),
	predicate_property(Module:H, defined).

source_of(Program, Head, Src) :-
	(   catch(p_term_src(Program, Head, S), _, fail)
	->  Src = S
	;   Src = unknown
	).

%	A program that imports `library(process)` and never calls it has done
%	nothing: the check is on what its predicates *call*, so an import only
%	matters when something reaches through it — and then `safe_goal/1` refuses
%	the caller, naming the goal. There is no separate import rule to write.

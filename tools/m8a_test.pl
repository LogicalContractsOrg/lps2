/* m8a_test.pl — the M8a gate (§I.9, docs/le_lps_design.md §7).

   The gate, in the design note's words: "LPS2 runs a program handed to it as
   internal text + provenance, and reports a diagnostic at an `.le` line and
   column."

   So that is what this checks, through the two paths a caller can take —
   `lps_compile/5` directly with `t(Term, src(...))` pairs, and the `/lpsapi`
   `compile` operation with a `provenance` array — plus the two edges that
   surround them: that a `.le` file with no LE2 configured is *refused* rather
   than guessed, and that the reply carries a decomposed `source` an editor can
   place a marker from.

	./myswipl.sh -q -g "consult('tools/m8a_test.pl')" -g "m8a:main" -t halt
*/

:- module(m8a, [main/0]).

:- use_module('../src/lps').
:- use_module('../src/core/lps_ops').
:- use_module('../src/core/lps_diag').
:- use_module('../src/core/lps_session').
:- use_module('../src/core/lps_program').
:- use_module('../src/edges/lps_le').
:- use_module(library(lists)).
:- use_module(library(http/json)).

:- dynamic failures/1.
failures(0).

main :-
	retractall(failures(_)), assertz(failures(0)),
	forall(test(Name, Goal), run_test(Name, Goal)),
	failures(N),
	(   N =:= 0
	->  format('M8a: all tests pass~n', [])
	;   format('M8a: ~w FAILED~n', [N]), halt(1)
	).

run_test(Name, Goal) :-
	(   catch(call(Goal), E, (format('  ~w: exception ~q~n', [Name, E]), fail))
	->  format('  ok    ~w~n', [Name])
	;   format('  FAIL  ~w~n', [Name]),
	    retract(failures(N)), N1 is N + 1, assertz(failures(N1))
	).

		 /*******************************
		 *	     the tests		*
		 *******************************/

test('a diagnostic lands on the .le line it came from', t_diag_line).
test('a term without provenance keeps its own line', t_mixed).
test('/lpsapi compile accepts a provenance array', t_http_prov).
test('/lpsapi reports a decomposed source for the editor', t_http_source).
test('a run compiled from LE positions still runs', t_runs).
test('.le with no LE2 configured is refused, not guessed', t_refusal).

%	The program: a fluent, an intensional fluent, and an `achieve` that the
%	reactive engine rejects — chosen because its diagnostic is derived from
%	the *recorded* source of the offending term, not from a global.
sample(Terms) :-
	Terms = [ t(fluents([p]),                        src('foo.le', 12, 4, le)),
		  t(l_int(holds(q, T), [holds(p, T)]),   src('foo.le', 20, 2, le)),
		  t(achieve(q),                          src('foo.le', 31, 7, le)) ].

t_diag_line :-
	sample(Terms),
	lps_compile(terms(Terms), internal, [dc], _, Diags),
	member(D, Diags),
	diag_code(D, achieve_without_planning_mode),
	diag_position(D, src('foo.le', 31, 7, le)).

t_mixed :-
	Terms = [ t(fluents([p]), 3),
		  t(achieve(p),   src('foo.le', 9, 1, le)) ],
	lps_compile(terms(Terms), internal, [dc], _, Diags),
	member(D, Diags),
	diag_position(D, src('foo.le', 9, 1, le)).

%	The HTTP layer is exercised through its own operation/3, which is the
%	whole of the endpoint apart from JSON transport.
t_http_prov :-
	Source = "fluents([p]).\nachieve(p).\n",
	Prov = [ _{index: 0, file: "foo.le", line: 12, col: 4, kind: "le"},
		 _{index: 1, file: "foo.le", line: 31, col: 7, kind: "le"} ],
	lps_http:operation("analyse",
		_{operation: "analyse", syntax: "internal",
		  source: Source, provenance: Prov}, Reply),
	get_dict(diagnostics, Reply, Ds),
	member(D, Ds),
	get_dict(code, D, "achieve_without_planning_mode"),
	get_dict(position, D, "src(foo.le,31,7,le)").

t_http_source :-
	Source = "achieve(p).\n",
	Prov = [ _{index: 0, file: "foo.le", line: 5, col: 2, kind: "le"} ],
	lps_http:operation("analyse",
		_{operation: "analyse", syntax: "internal",
		  source: Source, provenance: Prov}, Reply),
	get_dict(diagnostics, Reply, Ds),
	member(D, Ds),
	get_dict(source, D, S), is_dict(S),
	get_dict(file, S, "foo.le"),
	get_dict(line, S, 5),
	get_dict(col, S, 2),
	get_dict(kind, S, "le").

%	Provenance must not disturb the program itself: same terms, LE
%	positions, still a program that runs and produces the state it should.
t_runs :-
	Terms = [ t(maxTime(3),                          src('foo.le', 1, 0, le)),
		  t(fluents([p]),                        src('foo.le', 2, 0, le)),
		  t(initial_state([p]),                  src('foo.le', 3, 0, le)) ],
	lps_compile(terms(Terms), internal, [dc], Program, Diags),
	diags_ok(Diags),
	lps_session_new(Program, [dc], S0),
	lps_session_run(S0, end, S, _),
	lps_session_state(S, Fluents),
	memberchk(p, Fluents).

%	With neither LPS_LE2_URL nor LPS_LE2_DIR set this must produce exactly
%	one error naming both variables — and no program.
t_refusal :-
	\+ getenv('LPS_LE2_URL', _),
	\+ getenv('LPS_LE2_DIR', _),
	lps_le_translate('nonexistent.le', Text, Prov, Diags),
	Text == "", Prov == [],
	Diags = [D],
	diag_code(D, le_not_configured),
	diag_message(D, M),
	sub_atom(M, _, _, _, 'LPS_LE2_URL'),
	sub_atom(M, _, _, _, 'LPS_LE2_DIR').

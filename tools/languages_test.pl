/* languages_test.pl — Logical English for LPS in a language other than English.

   A program for LPS says the same thing in every language of Logical
   English: only the keywords and the author's own words change. So the test
   is exact. Each program of examples/de/ (Logisches Deutsch) is the
   translation of a program of examples/le/, with the same names after
   `bekannt als` / `known as`, and LE2 must read both into the same program:
   the same declarations, rules, laws, constraints and observations, term by
   term (up to the names of variables).

   The German programs are written as German is written. That is what this
   checks: the verb at the end of a clause after `wenn` and `dass` and first
   after `dann` and `anfangs`, the time in the middle of the sentence ("wird
   von einem ersten Zeitpunkt bis zu einem zweiten Zeitpunkt bekämpft"), the
   endings of "ein erster / der erste / dem ersten Zeitpunkt", `vom` and
   `zum`, and the commas between clauses (LE2's i18n/languages.csv:
   word_order, inflection_endings, clause_commas, contractions).

   Needs an LE2 checkout:

     LPS_LE2_LIB=/LogicalEnglish2 ./myswipl.sh -q -g "consult('tools/languages_test.pl')" -g "langt:main" -t halt
*/

:- module(langt, [main/0]).

:- use_module('../src/edges/lps_le').
:- use_module(library(lists)).
:- use_module(library(readutil)).

:- dynamic failures/1.
failures(0).

%   pair(German, English): the same program in the two languages.
pair('examples/de/feuer.le',        'examples/le/fire_simple.le').
pair('examples/de/ueberweisung.le', 'examples/le/bank_transfer.le').

main :-
	(   lps_le_available(lib(_))
	->  retractall(failures(_)), assertz(failures(0)),
	    forall(pair(De, En), run_pair(De, En)),
	    failures(N),
	    (   N =:= 0
	    ->  format('languages: all tests pass~n', [])
	    ;   format('languages: ~w FAILED~n', [N]), halt(1)
	    )
	;   format('languages: skipped (set LPS_LE2_LIB to an LE2 checkout)~n', [])
	).

run_pair(De, En) :-
	(   catch(same_program(De, En), E, (print_message(error, E), fail))
	->  format('  ok    ~w says what ~w says~n', [De, En])
	;   format('  FAIL  ~w and ~w differ~n', [De, En]),
	    retract(failures(N0)), N is N0 + 1, assertz(failures(N))
	).

same_program(De, En) :-
	program_terms(De, TsDe),
	program_terms(En, TsEn),
	(   TsDe =@= TsEn
	->  true
	;   forall(( nth1(I, TsDe, T), \+ ( nth1(I, TsEn, U), T =@= U ) ),
		   ( \+ \+ ( numbervars(T, 0, _), format('    only in ~w: ~q~n', [De, T]) ) )),
	    forall(( nth1(I, TsEn, T), \+ ( nth1(I, TsDe, U), T =@= U ) ),
		   ( \+ \+ ( numbervars(T, 0, _), format('    only in ~w: ~q~n', [En, T]) ) )),
	    fail
	).

%   The program a document is read into, as a list of terms, with no error.
program_terms(Rel, Terms) :-
	root(Root),
	atomic_list_concat([Root, '/', Rel], File),
	lps_le_translate(File, Text, _Provenance, Diags),
	(   member(diag(error, K, _, M, _), Diags)
	->  format('    ~w: ~w: ~w~n', [Rel, K, M]), fail
	;   true
	),
	text_terms(Text, Terms).

text_terms(Text, Terms) :-
	setup_call_cleanup(
	    open_string(Text, S),
	    read_all(S, Terms),
	    close(S)).

read_all(S, Terms) :-
	read_term(S, T, []),
	(   T == end_of_file
	->  Terms = []
	;   Terms = [T|Ts], read_all(S, Ts)
	).

root(Root) :-
	module_property(langt, file(Me)),
	file_directory_name(Me, Tools),
	file_directory_name(Tools, Root).

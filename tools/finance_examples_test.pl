/* finance_examples_test.pl — the gate of examples/finance/.

   Runs each scenario of the two programs there, as `./lps state` runs it,
   and compares the state it ends in with the values each README gives:

   - interest_rate_reset.le: the reset value of each scenario, as the CDM's
     Java tests work it out (the README's table), and the refusal of an
     overnight index without a method;
   - trade_lifecycle_record.le: no breach in the demo record, and the
     breaches each changed record is there to show.

   Needs an LE2 checkout:

     LPS_LE2_LIB=/path/to/LogicalEnglish2 \
       ./myswipl.sh -q -g "consult('tools/finance_examples_test.pl')" -g "fin:main" -t halt
*/

:- module(fin, [main/0]).

:- use_module(library(process)).
:- use_module(library(readutil)).
:- use_module(library(lists)).

main :-
	(   getenv('LPS_LE2_LIB', L), L \== ''
	->  findall(C, case(C), Cases),
	    maplist(check, Cases, Verdicts),
	    include(==(pass), Verdicts, Passes),
	    length(Passes, NP), length(Verdicts, N),
	    format('~n=== finance examples: ~w/~w ===~n', [NP, N]),
	    ( NP =:= N -> true ; halt(1) )
	;   format('finance examples: skipped (set LPS_LE2_LIB to an LE2 checkout)~n', [])
	).

%	case(File-Scenario-Outcome-MustHold-MustNotHold). `lps state` prints the
%	state a run ends in; a run that should end in success and prints no state
%	at all is a fault.
case('interest_rate_reset/interest_rate_reset.le'-'term rate'-success-
     [reset_output(term1, 0.055555555, date(2024,1,10))]-[]).
case('interest_rate_reset/interest_rate_reset.le'-'compounded'-success-
     [reset_output(sofr1, 0.0550084, date(2024,1,3))]-[]).
case('interest_rate_reset/interest_rate_reset.le'-'late rate'-success-
     [reset_output(sofr1, 0.0550084, date(2024,1,3))]-[]).
case('interest_rate_reset/interest_rate_reset.le'-'weekend'-success-
     [reset_output(sofr2, 0.0562632, date(2024,1,8))]-[]).
case('interest_rate_reset/interest_rate_reset.le'-'lookback'-success-
     [adjusted_observation(sofr3, date(2024,1,6), date(2024,1,10)),
      reset_output(sofr3, 0.052015, date(2024,1,12))]-[]).
case('interest_rate_reset/interest_rate_reset.le'-'compounded index'-success-
     [reset_output(index1, 0.0580645, date(2024,1,31))]-[]).
case('interest_rate_reset/interest_rate_reset.le'-'month end'-success-
     [adjusted_period(term2, date(2024,3,1), date(2024,3,30)),
      reset_output(term2, 0.0525, date(2024,3,30))]-[]).
case('interest_rate_reset/interest_rate_reset.le'-'overnight without method'-success-
     []-[unadjusted_observation(overnight1, _, _, _)]).
case('trade_lifecycle_record/trade_lifecycle_record.le'-'the demo record'-success-
     [notional('D6DIUNRZBM', 450000000), notional('Z131CJVJKM1', 100000000),
      live('GQ3ABGHD98')]-
     [breach(_, _), live('PG8NQNJP97'), live('BHNAFG4NEC')]).
case('trade_lifecycle_record/trade_lifecycle_record.le'-'no master agreement'-success-
     [breach('XTEST00001', a_master_agreement)]-[]).
case('trade_lifecycle_record/trade_lifecycle_record.le'-'applied too early'-success-
     [breach('XJKUGGSW2D', every_party_accepts_first),
      breach('XJKUGGSW2D', not_before_the_effective_date)]-[]).
case('trade_lifecycle_record/trade_lifecycle_record.le'-'terminated twice'-success-
     [breach('QUPLAGMH3R', less_than_the_notional), breach('QUPLAGMH3R', only_once)]-
     [breach('QUPLAGMH3Q', _)]).
case('trade_lifecycle_record/trade_lifecycle_record.le'-'dead trade'-success-
     [breach('NVTEST0001', a_live_trade), breach('NVTEST0001', proposed_by_a_party),
      breach('NVTEST0001', accepted_by_a_party)]-[]).

check(File-Scenario-Outcome-Must-MustNot, Verdict) :-
	root(Root),
	atomic_list_concat([Root, '/examples/finance/', File], Path),
	atomic_list_concat([Root, '/lps'], Lps),
	process_create(Lps, [state, Path, '--scenario', Scenario],
		       [stdout(pipe(Out)), stderr(pipe(Err)), process(Pid)]),
	read_string(Out, _, Text), close(Out),
	read_string(Err, _, _), close(Err),
	process_wait(Pid, _),
	split_string(Text, "\n", "", Lines),
	convlist(line_term, Lines, State),
	(   member(F, Must), \+ member(F, State)
	->  Verdict = missing(F)
	;   member(F, MustNot), member(F, State)
	->  Verdict = unexpected(F)
	;   State == [], Outcome == success
	->  Verdict = no_state
	;   Verdict = pass
	),
	format('~w ~w~t~70| ~w~n', [File, Scenario, Verdict]).

line_term(Line, Term) :-
	Line \== "",
	catch(term_string(Term, Line), _, fail),
	\+ Term = warning(_), compound(Term).

root(Root) :-
	module_property(fin, file(F)),
	file_directory_name(F, ToolsDir),
	file_directory_name(ToolsDir, Root).

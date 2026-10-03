/* assistant_prompt_test.pl — what the assistant's prompt holds for each kind of
   document.

   An LPS program gets the LPS reference. A Logical English document gets the
   Logical English references instead: the shape of a document for LPS
   (docs/user/reference/le-for-lps.md), LE2's language reference (from the LE2
   checkout this server compiles with) without the sections that do not apply,
   and only the reading sections of the LPS reference, marked as not to be
   written. Needs LPS_LE2_LIB (or LPS_LE2_DIR) to point at an LE2 checkout.

   Usage:
     LPS_LE2_LIB=/path/to/LogicalEnglish2 ./myswipl.sh -q -g run_tests -t halt tools/assistant_prompt_test.pl
*/

:- module(assistant_prompt_test, []).

:- use_module(library(plunit)).
:- use_module('../src/edges/lps_api').
:- use_module('../src/edges/lps_assistant').

prompt_for(Ctx, Prompt) :-
	lps_assistant:system_prompt(Ctx, b("", ""), none, _{}, Prompt).

:- begin_tests(assistant_prompt).

test(lps_program_gets_the_lps_reference, [nondet]) :-
	prompt_for(ctx(lps, 'x.pl', ''), P),
	sub_string(P, _, _, _, "=== THE LANGUAGE ==="),
	sub_string(P, _, _, _, "## 2."),          % lps.md, whole
	\+ sub_string(P, _, _, _, "THE SHAPE OF A DOCUMENT").

test(le_document_gets_the_shape_of_a_document, [nondet]) :-
	prompt_for(ctx(le, 'x.le', 'x.pl'), P),
	sub_string(P, _, _, _, "THE SHAPE OF A DOCUMENT"),
	sub_string(P, _, _, _, "## 1. The shape of a document"),
	sub_string(P, _, _, _, "## 3. Sentences"),
	\+ sub_string(P, _, _, _, "## 0. Where this came from"),
	\+ sub_string(P, _, _, _, "## 8. What has no LPS reading").

test(le_document_gets_le2s_language_reference,
     [nondet, condition(( lps_le:lps_le_available(How), memberchk(How, [lib(_), dir(_)]) ))]) :-
	prompt_for(ctx(le, 'x.le', 'x.pl'), P),
	sub_string(P, _, _, _, "HOW TO WRITE IT WELL"),
	sub_string(P, _, _, _, "## 2. Templates"),
	sub_string(P, _, _, _, "## 16. Humanizing LE"),
	\+ sub_string(P, _, _, _, "## 15. LE Extensions"),
	\+ sub_string(P, _, _, _, "## 17. Regulatory-decision constructs"),
	\+ sub_string(P, _, _, _, "## Table of Contents").

test(le_document_keeps_only_the_reading_sections_of_lps, [nondet]) :-
	prompt_for(ctx(le, 'x.le', 'x.pl'), P),
	sub_string(P, _, _, _, "FOR READING THE INTERNAL VIEW ONLY"),
	sub_string(P, _, _, _, "## 1."),
	\+ sub_string(P, _, _, _, "## 18.").   % lps.md's display table is not sent

:- end_tests(assistant_prompt).

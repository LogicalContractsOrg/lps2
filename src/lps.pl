/* lps.pl — load LPS(2).

   Loading this file gives you the core (§I.2) plus the syntax layer and the
   edges. The core alone is `src/core/`; nothing in it depends on anything
   outside it, which is what tools/lint_core.pl checks on every build.

   Layering, from the inside out:

     core/    the engine. No I/O, no threads, no clock, no foreign code.
     syntax/  external syntax ↔ the §I.3 internal representation.
     edges/   everything that touches the world: files, the CLI, HTTP.
*/

:- module(lps, []).

:- use_module(core/lps_ops).
:- use_module(core/lps_diag).
:- use_module(core/lps_terms).
:- use_module(core/lps_time).
:- use_module(core/lps_program).
:- use_module(core/lps_builtins).
:- use_module(core/lps_store).
:- use_module(core/lps_query).
:- use_module(core/lps_resolve).
:- use_module(core/lps_cycle).
:- use_module(core/lps_planner).
:- use_module(core/lps_explain).
:- use_module(core/lps_session).

:- use_module(syntax/lps_legacy_syntax).
:- use_module(syntax/lps_internal_syntax).
:- use_module(syntax/lps_pddl).
:- use_module(syntax/lps_drools).

:- use_module(edges/lps_source).
:- use_module(edges/lps_le).
:- use_module(edges/lps_llm).
:- use_module(edges/lps_assistant).
:- use_module(edges/lps_live).
:- use_module(edges/lps_cli).
:- use_module(edges/lps_http).

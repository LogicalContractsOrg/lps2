/* lps_ops.pl — the LPS operator table, as declared by legacy_lps1/utils/psyntax.P.

   The harness needs these to read and write both surface (`.pl`) and internal
   (`_.P`) LPS files: the internal syntax uses `not` as a prefix operator and the
   declarations `fluents [...]`, `actions [...]`, `events [...]` are prefix
   operators too.

   Per §I.4 the operator table is an *interface specification*, not engine code:
   diverging from it would break the requirement that legacy programs stay
   Prolog-readable. It is therefore copied deliberately, and this file is the single
   place where it lives for LPS(2).
*/

:- module(lps_ops, []).

% Surface syntax .pl
:- op(900,  fy,  user:(not)).
:- op(1200, xfx, user:(then)).
:- op(1185, fx,  user:(if)).
:- op(1190, xfx, user:(if)).
:- op(1100, xfy, user:else).
:- op(1050, xfx, user:(terminates)).
:- op(1050, xfx, user:(initiates)).
:- op(1050, xfx, user:(updates)).
:- op(1050, fx,  user:(observe)).
:- op(1050, fx,  user:(false)).
:- op(1050, fx,  user:initially).
:- op(1050, fx,  user:fluents).
:- op(1050, fx,  user:events).
:- op(1050, fx,  user:prolog_events).
:- op(1050, fx,  user:actions).
:- op(1050, fx,  user:unserializable).
:- op(999,  fx,  user:update).
:- op(999,  fx,  user:initiate).
:- op(999,  fx,  user:terminate).
:- op(997,  xfx, user:in).
:- op(995,  xfx, user:at).
:- op(995,  xfx, user:during).
:- op(995,  xfx, user:from).
:- op(994,  xfx, user:to).
:- op(1050, xfy, user:(::)).

% lps.js syntax extras
:- op(1200, xfx, user:(<-)).
:- op(1050, fx,  user:(<-)).
:- op(700,  xfx, user:(<=)).

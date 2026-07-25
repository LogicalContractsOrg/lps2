/* lps_ops.pl — the LPS operator table.

   §I.4 is explicit that this is the one place where the clean-room boundary
   does not apply: the operator table is an *interface specification*. The
   requirement is that legacy programs stay parseable directly by Prolog,
   exactly as today, and any divergence here breaks that requirement rather
   than demonstrating independence.

   It lives in `core/` rather than `syntax/` because it is needed to *read*
   the internal representation as well as the surface one. A generated `_.P`
   file contains `actions\n    [row(_,_)].` and `holds(not loc(goat,_), T)` —
   both of which only parse with these operators in scope.

   The lps.js operators (`<-`, `<=`) are deliberately absent: that syntax is
   dropped (§I.0 non-goals).
*/

:- module(lps_ops, [
	op(900,fy,not),
	op(1200,xfx,then),
	op(1185,fx,if),
	op(1190,xfx,if),
	op(1100,xfy,else),
	op(1050,xfx,terminates),
	op(1050,xfx,initiates),
	op(1050,xfx,updates),
	op(1050,fx,observe),
	op(1050,fx,false),
	op(1050,fx,initially),
	op(1050,fx,fluents),
	op(1050,fx,events),
	op(1050,fx,prolog_events),
	op(1050,fx,actions),
	op(1050,fx,unserializable),
	op(999,fx,update),
	op(999,fx,initiate),
	op(999,fx,terminate),
	op(997,xfx,in),
	op(995,xfx,at),
	op(995,xfx,during),
	op(995,xfx,from),
	op(994,xfx,to),
	op(1050,xfy,::),
	op(1050,fx,achieve)
	]).

%	Operators are module-local in SWI-Prolog, so they are exported
%	explicitly: every module that reads or writes LPS terms imports them.

:- op(900,  fy,  not).
:- op(1200, xfx, then).
:- op(1185, fx,  if).
:- op(1190, xfx, if).
%	conditional expressions: (if C then T else E). Slightly confusing next
%	to (if Antecedent then Consequent) rules, but the obligation to
%	parenthesise makes context carry it, and it reads best for newcomers.
:- op(1100, xfy, else).
:- op(1050, xfx, terminates).
:- op(1050, xfx, initiates).
:- op(1050, xfx, updates).
:- op(1050, fx,  observe).
:- op(1050, fx,  false).
:- op(1050, fx,  initially).
:- op(1050, fx,  fluents).
:- op(1050, fx,  events).
:- op(1050, fx,  prolog_events).
:- op(1050, fx,  actions).
:- op(1050, fx,  unserializable).
%	',' has priority 1000, so these sit just below it
:- op(999,  fx,  update).
:- op(999,  fx,  initiate).
:- op(999,  fx,  terminate).
:- op(997,  xfx, in).
:- op(995,  xfx, at).
:- op(995,  xfx, during).
:- op(995,  xfx, from).
:- op(994,  xfx, to).           % `from` binds looser than `to`
:- op(1050, xfy, ::).

%	§I.7.2's one genuine addition. Under lps_engine(reactive) — the default
%	— a program using it is a compile error, so no legacy program can
%	acquire planner semantics by accident.
:- op(1050, fx,  achieve).

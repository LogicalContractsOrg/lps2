% The wolf, goat and cabbage, stated rather than solved.
%
% §I.7.3. Every line except the last is existing LPS syntax, and most are
% verbatim from legacy_lps1/examples/forTesting/prospectiveGoat.pl. What has
% gone is the recursive `makeLoc` decomposition — three clauses telling the
% engine *how* to get an object across — replaced by two ordinary denials
% saying when an action is possible, and one `achieve`.
%
% Compare examples/goat.pl, where the declarative content (that the goat
% cannot be left with the wolf or the cabbage) never appears as a constraint
% at all: it has been compiled by hand into six `dealWithGoat` cases.

:- lps_engine(planning, [search(bfs), horizon(10), max_concurrency(2)]).

maxTime(10).

actions row(_,_), transport(_,_,_).
fluents loc(_,_).

initially loc(wolf,south), loc(goat,south), loc(cabbage,south), loc(farmer,south).

% causal laws — verbatim from prospectiveGoat.pl
transport(Object, L1, L2) updates L1 to L2 in loc(Object, L1).
row(L1, L2)               updates L1 to L2 in loc(farmer, L1).

% action interference — verbatim
false transport(O1, L1, L2), transport(O2, L1, L2), O1 \= O2.
false row(south, north), row(north, south).

% the puzzle constraints, in the prospective form: a denial about the state
% the crossing *would* produce
false loc(goat,L) at T, loc(wolf,L) at T,    not loc(farmer,L) at T, row(_,_) to T.
false loc(goat,L) at T, loc(cabbage,L) at T, not loc(farmer,L) at T, row(_,_) to T.

% the farmer is not cargo. In prospectiveGoat.pl this hides inside the
% makeLoc decomposition as `Object \= farmer`; saying it out loud is part of
% the price of dropping the decomposition, and arguably an improvement.
false transport(farmer, _, _).

% applicability, replacing the makeLoc decomposition — ordinary denials
false transport(Object, L1, _) from T1 to _,  not loc(farmer, L1) at T1.
false transport(_, L1, L2)     from T1 to T2, not row(L1, L2) from T1 to T2.
false row(L1, _)               from T1 to _,  not loc(farmer, L1) at T1.

% the one new construct
achieve loc(wolf,north), loc(goat,north), loc(cabbage,north), loc(farmer,north).

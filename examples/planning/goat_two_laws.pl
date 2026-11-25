% The farmer, the wolf, the goat and the cabbage, as a planning problem: the
% program of examples/start/goat_declarative.pl with two differences.
%
%  1. Each action has one law that initiates and one law that terminates,
%     in place of one `updates` law. Logical English writes the puzzle this
%     way (examples/le/goat_declarative.le).
%  2. The planner has no limit on the number of actions in a cycle. The
%     first constraint alone must stop two cargoes in one crossing.
%
% tools/examples_test.pl runs this program: the plan is the same seven
% crossings.
:- lps_engine(planning, [search(bfs)]).

maxTime(10).

actions row(_,_), transport(_,_,_).
fluents loc(_,_).

initially loc(wolf,south), loc(goat,south), loc(cabbage,south), loc(farmer,south).

transport(O, L1, L2) initiates loc(O, L2).
transport(O, L1, L2) terminates loc(O, L1).
row(L1, L2) initiates loc(farmer, L2).
row(L1, L2) terminates loc(farmer, L1).

false transport(O1, L1, L2), transport(O2, L1, L2), O1 \= O2.
false row(south, north), row(north, south).

false row(_,_) to T, loc(goat,L) at T, loc(wolf,L) at T, not loc(farmer,L) at T.
false row(_,_) to T, loc(goat,L) at T, loc(cabbage,L) at T, not loc(farmer,L) at T.

false transport(farmer, _, _).

false transport(Object, L1, _) from T1 to _,  not loc(farmer, L1) at T1.
false transport(_, L1, L2)     from T1 to T2, not row(L1, L2) from T1 to T2.
false row(L1, _)               from T1 to _,  not loc(farmer, L1) at T1.

achieve loc(wolf,north), loc(goat,north), loc(cabbage,north), loc(farmer,north).

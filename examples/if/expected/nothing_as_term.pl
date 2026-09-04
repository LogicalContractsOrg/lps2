%  nothing_as_term — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_wait]).
events(3, [wait(player)]).
events(4, [end_turn]).
events(6, [begin_turn,cmd_take(banana)]).
events(7, [take(player,banana)]).
events(8, [end_turn]).
events(10, [begin_turn,cmd_take(peach)]).
events(11, [take(player,peach)]).
events(12, [end_turn]).
events(14, [begin_turn,cmd_insert(banana,box)]).
events(15, [insert(player,banana,box)]).
events(16, [end_turn]).
fluents([in(player,home),carries(player,box),carries(player,peach),turn(4),in(banana,box)]).

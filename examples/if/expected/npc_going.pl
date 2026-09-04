%  npc_going — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_wait]).
events(3, [wait(player)]).
events(4, [end_turn]).
events(5, [go(thief,east)]).
events(6, [begin_turn,cmd_wait]).
events(7, [wait(player)]).
events(8, [end_turn]).
events(9, [go(thief,east)]).
fluents([in(player,twisted),turn(2),in(thief,twisty)]).

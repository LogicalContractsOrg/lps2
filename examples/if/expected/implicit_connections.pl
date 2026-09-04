%  implicit_connections — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_go(north)]).
events(3, [go(player,north)]).
events(4, [end_turn]).
events(6, [begin_turn,cmd_go(south)]).
events(7, [go(player,south)]).
events(8, [end_turn]).
events(10, [begin_turn,cmd_go(east)]).
events(11, [go(player,east)]).
events(12, [end_turn]).
events(14, [begin_turn,cmd_go(west)]).
events(15, [go(player,west)]).
events(16, [end_turn]).
fluents([turn(4),in(player,temple)]).

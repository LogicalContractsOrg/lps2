%  doors — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_go(east)]).
events(3, [refuse_go(player,east)]).
events(4, [end_turn]).
events(6, [begin_turn,cmd_open(oak_door)]).
events(7, [open(player,oak_door)]).
events(8, [end_turn]).
events(10, [begin_turn,cmd_go(east)]).
events(11, [go(player,east)]).
events(12, [end_turn]).
events(14, [begin_turn,cmd_go(west)]).
events(15, [go(player,west)]).
events(16, [end_turn]).
fluents([in(oak_door,hall),turn(4),in(player,hall)]).

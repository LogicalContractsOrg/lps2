%  scene — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_wait]).
events(3, [wait(player)]).
events(4, [end_turn]).
events(6, [begin_turn,cmd_take(ball)]).
events(7, [take(player,ball)]).
events(8, [end_turn,terminate(playing(starting)),initiate(ended(starting,roundly))]).
events(9, [initiate(playing(ending)),is_announced(roundly)]).
fluents([in(player,home),in(cube,home),turn(2),carries(player,ball),ended(starting,roundly),playing(ending)]).

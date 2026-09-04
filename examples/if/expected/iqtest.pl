%  iqtest — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_open(case)]).
events(3, [refuse_open(player,case)]).
events(4, [end_turn]).
events(6, [begin_turn,cmd_take(donuts)]).
events(7, [refuse_take(player,donuts)]).
events(8, [end_turn]).
events(10, [begin_turn,ask_get(ogg,donuts)]).
events(11, [unlock(ogg,case,silver_key)]).
events(12, [end_turn,open(ogg,case)]).
events(13, [take(ogg,donuts)]).
events(14, [begin_turn,ask_give(ogg,donuts,player)]).
events(15, [give(ogg,donuts,player)]).
events(16, [end_turn]).
events(18, [begin_turn,cmd_eat(donuts)]).
events(19, [eat(player,donuts)]).
events(20, [end_turn]).
fluents([in(player,shop),in(ogg,shop),in(case,shop),carries(ogg,silver_key),turn(5)]).

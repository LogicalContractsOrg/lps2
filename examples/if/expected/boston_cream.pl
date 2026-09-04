%  boston_cream — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_open(basket)]).
events(3, [open(player,basket)]).
events(4, [end_turn]).
events(6, [begin_turn,cmd_take(silver_key)]).
events(7, [take(player,silver_key)]).
events(8, [end_turn]).
events(9, [growl(ogg)]).
events(10, [begin_turn,cmd_unlock(case,silver_key)]).
events(11, [unlock(player,case,silver_key)]).
events(12, [end_turn]).
events(14, [begin_turn,cmd_open(case)]).
events(15, [open(player,case)]).
events(16, [end_turn]).
events(17, [take(ogg,donuts)]).
events(18, [begin_turn,cmd_enter(case)]).
events(19, [enter(player,case)]).
events(20, [end_turn]).
events(21, [eat(ogg,donuts)]).
events(22, [begin_turn,cmd_close(case)]).
events(23, [shut(player,case)]).
events(24, [end_turn]).
events(26, [begin_turn,cmd_lock(case,silver_key)]).
events(27, [lock(player,case,silver_key)]).
events(28, [end_turn]).
fluents([in(ogg,shop),in(case,shop),in(basket,shop),carries(player,silver_key),in(player,case),closed(case),turn(7),hunger(ogg,2),locked(case)]).

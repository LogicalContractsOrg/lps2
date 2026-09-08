%  boston_cream — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_open(basket)]).
events(3, [open(player,basket)]).
events(4, [end_turn]).
events(6, [begin_turn,cmd_take('the silver key')]).
events(7, [take(player,'the silver key')]).
events(8, [end_turn]).
events(9, [growls(ogg)]).
events(10, [begin_turn,cmd_unlock(case,'the silver key')]).
events(11, [unlock(player,case,'the silver key')]).
events(12, [end_turn]).
events(14, [begin_turn,cmd_open(case)]).
events(15, [open(player,case)]).
events(16, [end_turn]).
events(17, [take(ogg,donuts)]).
events(18, [begin_turn,cmd_enter(case)]).
events(19, [enter(player,case)]).
events(20, [end_turn]).
events(21, [eats(ogg,donuts)]).
events(22, [begin_turn,cmd_close(case)]).
events(23, [shut(player,case)]).
events(24, [end_turn]).
events(26, [begin_turn,cmd_lock(case,'the silver key')]).
events(27, [lock(player,case,'the silver key')]).
events(28, [end_turn]).
fluents([in(ogg,shop),in(case,shop),in(basket,shop),carries(player,'the silver key'),in(player,case),closed(case),turn(7),the_hunger_of_is(ogg,2),locked(case)]).

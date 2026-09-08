%  iqtest — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_open(case)]).
events(3, [refuse_open(player,case)]).
events(4, [end_turn]).
events(6, [begin_turn,cmd_take(donuts)]).
events(7, [refuse_take(player,donuts)]).
events(8, [end_turn]).
events(10, [begin_turn,is_asked_to_get(ogg,donuts)]).
events(11, [unlock(ogg,case,'the silver key')]).
events(12, [end_turn,open(ogg,case)]).
events(13, [take(ogg,donuts)]).
events(14, [begin_turn,is_asked_to_give_to(ogg,donuts,player)]).
events(15, [gives_to(ogg,donuts,player)]).
events(16, [end_turn]).
events(18, [begin_turn,the_command_is_to_eat(donuts)]).
events(19, [eats(player,donuts)]).
events(20, [end_turn]).
fluents([in(player,shop),in(ogg,shop),in(case,shop),carries(ogg,'the silver key'),turn(5)]).

%  regarding — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_wait]).
events(3, [wait(player)]).
events(4, [end_turn]).
events(6, [begin_turn,cmd_take(torch)]).
events(7, [take(player,torch)]).
events(8, [end_turn]).
events(10, [begin_turn,cmd_take(banana)]).
events(11, [take(player,banana)]).
events(12, [end_turn]).
events(14, [begin_turn,cmd_drop(banana),cmd_drop(torch)]).
events(15, [drop(player,torch),drop(player,banana)]).
events(16, [end_turn]).
events(18, [begin_turn,cmd_take(grapes)]).
events(19, [take(player,grapes)]).
events(20, [end_turn]).
fluents([in(player,foo),in(torch,foo),in(banana,foo),turn(5),carries(player,grapes)]).

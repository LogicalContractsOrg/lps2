%  negated_rp — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_open(jewel_box)]).
events(3, [open(player,jewel_box)]).
events(4, [end_turn]).
events(6, [begin_turn,cmd_open(broken_box)]).
events(7, [refuse_open(player,broken_box)]).
events(8, [end_turn]).
events(10, [begin_turn,cmd_open(secret_box)]).
events(11, [refuse_open(player,secret_box)]).
events(12, [end_turn]).
fluents([in(player,start),in(jewel_box,start),in(broken_box,start),in(secret_box,start),closed(broken_box),closed(secret_box),turn(3)]).

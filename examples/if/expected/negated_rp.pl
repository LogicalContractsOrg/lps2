%  negated_rp — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_open('the jewel box')]).
events(3, [open(player,'the jewel box')]).
events(4, [end_turn]).
events(6, [begin_turn,cmd_open('the broken box')]).
events(7, [refuse_open(player,'the broken box')]).
events(8, [end_turn]).
events(10, [begin_turn,cmd_open('the secret box')]).
events(11, [refuse_open(player,'the secret box')]).
events(12, [end_turn]).
fluents([in(player,start),in('the jewel box',start),in('the broken box',start),in('the secret box',start),closed('the broken box'),closed('the secret box'),turn(3)]).

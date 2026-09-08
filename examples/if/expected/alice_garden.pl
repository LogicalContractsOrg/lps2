%  alice_garden — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_wait]).
events(3, [wait(player)]).
events(4, [end_turn]).
events(5, [run('the white rabbit',offstage,riverbank)]).
events(6, [begin_turn,cmd_wait]).
events(7, [wait(player)]).
events(8, [end_turn]).
events(9, [run('the white rabbit',riverbank,'the rabbit hole')]).
events(10, [begin_turn,cmd_go(down)]).
events(11, [go(player,down)]).
events(12, [end_turn]).
events(13, [run('the white rabbit','the rabbit hole',hall)]).
events(14, [begin_turn,cmd_go(down)]).
events(15, [go(player,down)]).
events(16, [end_turn,terminate(playing('the first chapter')),initiate(ended('the first chapter',below)),initiate(playing('the second chapter'))]).
events(17, [run('the white rabbit',hall,garden)]).
events(18, [begin_turn,cmd_take('the golden key')]).
events(19, [take(player,'the golden key')]).
events(20, [end_turn]).
events(22, [begin_turn,the_command_is_to_drink(bottle)]).
events(23, [drink(player,bottle)]).
events(24, [end_turn]).
events(26, [begin_turn,cmd_unlock('the small door','the golden key')]).
events(27, [unlock(player,'the small door','the golden key')]).
events(28, [end_turn]).
events(30, [begin_turn,cmd_open('the small door')]).
events(31, [open(player,'the small door')]).
events(32, [end_turn]).
events(34, [begin_turn,cmd_go(south)]).
events(35, [go(player,south)]).
events(36, [end_turn,terminate(playing('the second chapter')),initiate(ended('the second chapter','in the garden'))]).
fluents([in(sister,riverbank),size('the white rabbit',small),carries('the white rabbit','the pocket watch'),carries('the white rabbit',fan),carries('the white rabbit',gloves),in('the small door',hall),in('the glass table',hall),in(cake,hall),in(mouse,'the pool of tears'),ended('the first chapter',below),in('the white rabbit',garden),carries(player,'the golden key'),size(player,small),turn(9),in(player,garden),ended('the second chapter','in the garden')]).

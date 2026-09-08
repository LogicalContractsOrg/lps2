%  alice — recorded by tools/if_test.pl; regenerate only on purpose.
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
events(18, [begin_turn,the_command_is_to_drink(bottle)]).
events(19, [drink(player,bottle)]).
events(20, [end_turn]).
events(22, [begin_turn,cmd_take('the golden key')]).
events(23, [refuse_take(player,'the golden key')]).
events(24, [end_turn]).
events(26, [begin_turn,the_command_is_to_eat(cake)]).
events(27, [eat(player,cake)]).
events(28, [end_turn]).
events(29, [cry(player)]).
events(30, [begin_turn,cmd_wait]).
events(31, [wait(player)]).
events(32, [end_turn]).
events(33, [run('the white rabbit',garden,hall)]).
events(34, [begin_turn,cmd_take(fan),drop('the white rabbit',fan),drop('the white rabbit',gloves)]).
events(35, [take(player,fan)]).
events(36, [end_turn]).
events(37, [run('the white rabbit',hall,garden)]).
events(38, [begin_turn,the_command_is_to_wave(fan)]).
events(39, [wave(player,fan)]).
events(40, [end_turn]).
events(41, [fall(player,'the pool of tears')]).
events(42, [terminate(playing('the second chapter')),initiate(ended('the second chapter',wet))]).
fluents([in(sister,riverbank),size('the white rabbit',small),carries('the white rabbit','the pocket watch'),in('the small door',hall),closed('the small door'),locked('the small door'),in('the glass table',hall),on('the golden key','the glass table'),in(mouse,'the pool of tears'),ended('the first chapter',below),cried(player),pool,in(gloves,hall),carries(player,fan),in('the white rabbit',garden),turn(10),size(player,small),in(player,'the pool of tears'),ended('the second chapter',wet)]).

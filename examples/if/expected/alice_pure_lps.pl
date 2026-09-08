%  alice_pure_lps — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [run('the white rabbit',offstage,riverbank)]).
events(3, [run('the white rabbit',riverbank,'the rabbit hole')]).
events(6, [cmd_go(down)]).
events(7, [go(player,down)]).
events(8, [run('the white rabbit','the rabbit hole',hall)]).
events(10, [cmd_go(down)]).
events(11, [go(player,down)]).
events(12, [terminate(playing('the first chapter')),initiate(ended('the first chapter',below)),initiate(playing('the second chapter')),run('the white rabbit',hall,garden)]).
events(14, [the_command_is_to_drink(bottle)]).
events(15, [drink(player,bottle)]).
events(18, [cmd_take('the golden key')]).
events(19, [refuse_take(player,'the golden key')]).
events(22, [the_command_is_to_eat(cake)]).
events(23, [eat(player,cake)]).
events(24, [cry(player)]).
events(25, [run('the white rabbit',garden,hall)]).
events(26, [drop('the white rabbit',fan),drop('the white rabbit',gloves),run('the white rabbit',hall,garden)]).
events(30, [cmd_take(fan)]).
events(31, [take(player,fan)]).
events(34, [the_command_is_to_wave(fan)]).
events(35, [wave(player,fan)]).
events(36, [fall(player,'the pool of tears')]).
events(37, [terminate(playing('the second chapter')),initiate(ended('the second chapter',wet))]).
fluents([in(sister,riverbank),size('the white rabbit',small),carries('the white rabbit','the pocket watch'),in('the small door',hall),closed('the small door'),locked('the small door'),in('the glass table',hall),on('the golden key','the glass table'),in(mouse,'the pool of tears'),ended('the first chapter',below),cried(player),pool,in(gloves,hall),in('the white rabbit',garden),carries(player,fan),size(player,small),in(player,'the pool of tears'),ended('the second chapter',wet)]).

%  alice_garden — recorded by tools/if_test.pl; regenerate only on purpose.
status(success).
events(2, [begin_turn,cmd_wait]).
events(3, [wait(player)]).
events(4, [end_turn]).
events(5, [run(white_rabbit,offstage,riverbank)]).
events(6, [begin_turn,cmd_wait]).
events(7, [wait(player)]).
events(8, [end_turn]).
events(9, [run(white_rabbit,riverbank,rabbit_hole)]).
events(10, [begin_turn,cmd_go(down)]).
events(11, [go(player,down)]).
events(12, [end_turn]).
events(13, [run(white_rabbit,rabbit_hole,hall)]).
events(14, [begin_turn,cmd_go(down)]).
events(15, [go(player,down)]).
events(16, [end_turn,terminate(playing(chapter_one)),initiate(ended(chapter_one,below)),initiate(playing(chapter_two))]).
events(17, [run(white_rabbit,hall,garden)]).
events(18, [begin_turn,cmd_take(golden_key)]).
events(19, [take(player,golden_key)]).
events(20, [end_turn]).
events(22, [begin_turn,cmd_drink(bottle)]).
events(23, [drink(player,bottle)]).
events(24, [end_turn]).
events(26, [begin_turn,cmd_unlock(small_door,golden_key)]).
events(27, [unlock(player,small_door,golden_key)]).
events(28, [end_turn]).
events(30, [begin_turn,cmd_open(small_door)]).
events(31, [open(player,small_door)]).
events(32, [end_turn]).
events(34, [begin_turn,cmd_go(south)]).
events(35, [go(player,south)]).
events(36, [end_turn,terminate(playing(chapter_two)),initiate(ended(chapter_two,in_the_garden))]).
fluents([in(sister,riverbank),size(white_rabbit,small),carries(white_rabbit,pocket_watch),carries(white_rabbit,fan),carries(white_rabbit,gloves),in(small_door,hall),in(glass_table,hall),in(cake,hall),in(mouse,pool_of_tears),ended(chapter_one,below),in(white_rabbit,garden),carries(player,golden_key),size(player,small),turn(9),in(player,garden),ended(chapter_two,in_the_garden)]).

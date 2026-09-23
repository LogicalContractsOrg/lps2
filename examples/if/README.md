# Interactive fiction — the library and the stories, on LPS

Text adventures written in Logical English and run by LPS. `world.le` is the
library: rooms, things, doors, people, a dozen actions, as in Inform 7's
standard rules. `turns.le` is the clock, counted in turns. Every other `.le`
file is a story that includes the library, and most of them are Inform 7
programs brought across.

## Start here
- [Doors](doors.le): the smallest story, a hall and a door that must be
  opened before you can go east.
- [Alice](alice.le): chapters one and two of *Alice's Adventures in
  Wonderland*, the showcase.
- [IQ Test](iqtest.le): a character asked to fetch something through a
  locked case.
- [The Inform sources](inform/): the Inform 7 programs these stories are
  read from.

## Try this
1. Open [Doors](doors.le) and press **Play** in the top bar. The play panel
   opens on the hall.
2. Type `e`. The door is closed, so there is no way east, and the story
   says so.
3. Type `why`. The answer names the rule and the fact that refused the move.
4. Type `open door`, then `e`. Now you are in the garden.
5. Open [Alice](alice.le), press **Play**, and play until Alice finds the
   bottle. Press **Fork** to start a second game from there, play it
   differently, and press **Diff** to see what happened in one game and not
   in the other.

## More
- [Details](DETAILS.md): every story, how commands are read, and the
  conventions of the library.
- [LPS for Inform users](/docs/user/tutorials/inform-users): the tutorial.
- [Inform 7 and LPS](/docs/user/integrations/inform-7): how an Inform source
  becomes a story.

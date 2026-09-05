# Introducing interactive fiction on LPS — the demo, step by step

The recording is `docs/introducingIFonLPS.mp4` (about five minutes, 1440 by 900). It is produced, not filmed: `tools/if_demo.cjs` holds the plan below as a list of steps, synthesises each step's narration, drives the IDE through Playwright while recording, and lays the speech on the picture with ffmpeg at the moment each step began. Rerun it after a UI change, the way the documentation screenshots are rerun.

Each step is one user event and what the presenter says while doing it.

## 1. principles

*The IDE opens on the Alice story.*

Hello. What you see is LPS, the Logic Production System, running in a browser, and the subject today is interactive fiction: text adventures, of the kind Inform 7 is used to write. The principles are simple. A story is a document in Logical English, written on a small library that plays the part of Inform's standard rules: rooms, things, doors, containers, people. A turn is a burst of engine cycles. What the player types becomes an event. Reactive rules respond to it, causal laws change the state, and constraints, written as "it must not be true that", refuse what the world does not allow. Nothing here is scripted: the narration is read off the trace, and a refusal is the engine's own explanation of why the action did not happen. The machinery that explains a legal rule, or a robot's plan, is the machinery that tells the story.

## 2. alice source

*The presenter scrolls through the header and the declarations of alice.le.*

This is Alice's Adventures in Wonderland, chapters one and two, as a story. The header says what it is for: the same choices as the book, or different ones. The logic is all in the English document. Below the header come the story's own commands, and a few dozen assertions: the rooms, the things, and who is where.

## 3. companion

*The companion tab, alice.lps, is opened and scrolled.*

The companion file holds the words: Carroll's narration, keyed on the actions, and a description of how the state is to be drawn. Nothing in this file changes what happens.

## 4. start

*Back on alice.le, Play is pressed, then Start. The opening appears; the Timeline pane fills.*

I go back to the story, press Play, and start. The opening is what the rules did before the first turn, and where you are. On the right, the timeline already shows the cycles that ran.

## 5. wait

*The presenter types "wait".*

I wait one turn. Time passes, and the White Rabbit runs by, in Carroll's words. That sentence is not scripted: the rabbit's rule fired, the action is in the trace, and the companion has a line for that action.

## 6. guess

*The presenter types "jump down the rabbit hole"; the placeholder shows the model at work; the pick is played.*

Now I type something the parser does not know: jump down the rabbit hole. The parser is deterministic, and it gives up. But with a language-model key set, the line, and the commands the story could take right now, are shown to a model, which picks one, or none. The placeholder says: let me see if I understand. It took it as: go down. And the story accepts, or refuses, that command on its own terms, exactly as if I had typed it.

## 7. commands

*Commands is pressed; the list appears; "wait" is clicked.*

The Commands button lists what would work from here. Each line was checked against the story's constraints on the current state, something Inform cannot do, because Inform cannot try an action without doing it. A click on one does it: I wait again, and the Rabbit hurries on.

## 8. timeline

*The Timeline pane; the slider is nudged back twelve cycles; the first turn in the log is clicked.*

The panes follow the game. The timeline shows which facts held in which cycles, and which events occurred. Moving the slider back marks, in the log, the turn that cycle belonged to. And a click on a turn in the log takes the slider to the end of that turn.

## 9. 2d

*The 2D pane; Alice is clicked.*

The 2D view draws the state at the current cycle, from the drawing clauses in the companion. A click on Alice takes the log to the turn in which she last changed, and says which facts changed then.

## 10. changes

*The Changes pane.*

Changes lists what each cycle started and stopped: the state transitions, one cycle at a time, with the rule that caused each.

## 11. why

*Why? is pressed.*

And Why asks the engine about the last turn: which rule fired, from which goal, in which cycle. This is the explanation facility the engine offers to any program; a story is just a program.

## 12. iqtest

*Stop. The IQ Test as converted from Inform source opens; its header and scenario are scrolled.*

The second story did not start as Logical English. It is IQ Test, from Inform's recipe book, and this document was generated from the Inform source by the LPS front end: Inform's assertions became a story on the library, and its test script became the scenario.

## 13. original

*View, then "The original this was converted from"; the Inform source is shown, then dismissed.*

Under View, the original, as Inform wrote it. The two Before rules in it, about opening the case and giving what is asked for, were not translated: the library's fetch plan does what they did by hand.

## 14. open case

*The hand-completed iqtest.le opens; Play, Start; "open case" is typed.*

The generated story has the world but not the three verbs those rules supplied: the order, the giving, and eating. The hand-completed version in the examples adds them, in three lines of templates, and that is the one I play. Start. The donuts are in a locked case. Open case is refused, and the refusal comes with its reason: the case is locked.

## 15. ask ogg

*"og, get donuts" is typed.*

So I ask Ogg. An order to a character is a goal for him. He unlocks the case with the key he carries, opens it, and takes the donuts. That is a plan the engine found, not a script.

## 16. eat

*"og, give me the donuts", then "eat donuts".*

He gives me the donuts when asked, and I eat them. That is the end of Inform's own test script, reached with the same commands.

## 17. close

*The Timeline pane, as the closing words are said.*

That is interactive fiction on LPS: a story is a logic program, a turn is a run, and every sentence in the log can be traced to a rule. The examples, and a guide for Inform authors, are in the repository. Thank you.


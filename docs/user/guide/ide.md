# Using the editor

*Kind: guide · Audience: users · Status: current (2026-09-16)*

The command `./lps ide` starts a server on <http://localhost:3060>. LPS is short
for Logic Production Systems. This document describes each part of the screen that
the server shows. The last part, **[how do I …](#how-do-i-)**, gives answers to the
questions that people usually have.

**<http://localhost:3060/> is a start page, not the editor.** The start page shows
a list of all the programs on the server, in folders. The folders that you left
open are still open. The start page also shows a list of the documents. The editor
is at <http://localhost:3060/ide>. Each link on the start page opens the editor
with that program in it. The box above the programs **searches the examples**. The
box under *Documentation* searches the documents in the same way.

To search, type some words, or a phrase in quotation marks. Then select where to
look: everywhere, in the names, in the declarations, or in the text. The programs
that match show below the box, with the best match first. Each program shows the
line that matched. Click a program to see its first lines. To open the program in
the editor, double-click it, push Enter, or click the *Open* button. The editor
uses the same panel to select a program (*File ▸ Open example from server*, below).

![The start page](../images/landing.png)

The editor does each of its tasks with a request to one web address,
`POST /lpsapi`. Thus no item in this document is available only from the editor.
You can also send each of these requests from the command line, with `curl`. This
rule makes sure that the editor does not become, without notice, the only way to
use the system.

![The editor](../images/ide-overview.png)

---

## Contents

- [The start page](#the-start-page)
- [Signing in](#signing-in)
- [The layout](#the-layout)
- [Running a program](#running-a-program)
- [The editor itself](#the-editor-itself)
- [The six panes](#the-six-panes)
- [Asking why](#asking-why)
- [Logical English](#logical-english)
- [The assistant](#the-assistant)
- [Sessions that do not stop](#sessions-that-do-not-stop)
- [The menus](#the-menus)
- [How do I …](#how-do-i-)
- [Keyboard shortcuts](#keyboard-shortcuts)

---

## The start page

The page `/` shows the programs as a tree of folders. The examples of LPS2, the
second version, are first. They are in groups by purpose: *Start here*, *Logical
English*, *Interactive fiction*, *Planning*, *Agents*, *Collections* and *Migration
twins*. PDDL, in *Planning*, is short for the Planning Domain Definition Language.
*Agents* contains the examples that use a large language model, and the Minecraft
examples. Each folder gets its name from its own README file. The examples of LPS1,
the first version, are after the LPS2 examples, with their own folders.

Each folder keeps its open or closed state in this browser. Add `?expand=all` to
the address to open all the folders at the same time. Each folder has a small link
symbol (🔗) after its name. Click the symbol to copy the web address of that
folder. You can then paste the address into a message. The address is the start
page with `?dir=` and the path of the folder.

When you open that address, the page opens the folder and the folders around it.
The page then moves to show the folder. The browser command **Copy link** (on the
right-click menu of the symbol) copies the same address.

A README is a short text that tells what is in a folder. A folder that has a README
also has a **📖 About this folder** button after its name. The button opens the
README in a panel next to the list. The folder does not open or close. The README
tells you where to start, gives some steps to try, and gives more documents to read.
A link in the README to a program opens that program in the editor.

To close the panel, click **Close** or push the Escape key. The address `?readme=`
with the path of the folder opens the panel. The link symbol (🔗) at the top of the
panel copies that address. You can then paste the address into a message. The
column on the right tells you where to start and what to read.

## Signing in

The top right of the start page and of the top bar of the editor shows **Sign in**.
When you are signed in, it shows your email address and **Sign out**. It is not
necessary to sign in. All the examples and all the features in this manual operate
without sign-in. The exceptions are the few features that are part of a licence.

The sign-in is the same as the sign-in of the Logical English editor at
`le2.logicalcontracts.com`. When you sign in on one site, you are also signed in on
the other site. You can sign in in three ways:

- With a Google account.
- With a GitHub account.
- With an email address and a password that Logical Contracts made for you.

A licence is attached to the email address that you use to sign in. A licence has
an expiry date. The licence *with extensions* adds **Misc ▸ Deploy as Solidity**,
the Drools reader (File ▸ Open of a `.drl` file), and the translators of other
systems. File ▸ Open and Export show these translators. Without this licence,
Deploy as Solidity is grey. Put the mouse pointer on the item to see the reason.

The licence *InsurLE* adds the InsurLE extensions to Logical English. The Logical
English guide *Signing in, and what a licence adds* gives all the data about the
two licences. Put the mouse pointer on your email address at the top right to see
a list of your licences.

## The layout

The screen has one row of controls and two columns.

**The row of controls at the top** is the only place where you operate the editor.
From the left, the row has these controls:

1. The menus.
2. `maxTime` and **Run**, and the scenario list when there is a scenario.
3. The result of the last run.
4. **Live**, which opens the live panel.
5. **Play**, which opens the play panel.

**Play** is grey unless the document on the screen is a story. Put the mouse
pointer on **Play** to see this reason. A story is a Logical English document that
includes the interactive-fiction library, with the line
`includes these resources: world`.

In the play panel, **Commands** shows a list of the commands that operate from your
current position. The list contains each command that succeeds when the editor
tries it on a copy of the game. Click a command, and the game does it. When you
type `commands`, you get the same list. The panes follow the game. After each
turn, the Timeline, Changes, Automaton, 2D and 3D panes show the game until that
turn. The slider moves through the game.

The transcript records the turns. Each line that you type shows its turn number and
the number of cycles that the turn used. The start of the game has its own heading.
Thus the transcript and the panes can refer to each other:

- Click in the Timeline, or move the slider a small distance. The transcript marks
  the turn of that cycle.
- Click the line of a turn. The panes go to the end of that turn.
- Click a thing in the 2D or 3D pane. The transcript marks the turn in which that
  thing changed last, until the cycle of the slider. It also tells what changed.
  To see the history of the thing, move the slider back and click again.

The **View** menu also shows the three panels that you can open: **Assistant
panel**, **Live execution panel** and **Play panel**. When a button is bright, its
panel is open. A closed panel uses no space and shows no controls.

**The play panel** is for a story. A story is a Logical English document that
includes the interactive-fiction library (`examples/if/`; refer to
`docs/project/plans/InformPlan.md` for the reason). Start plays the document that
is in the editor. Type the words that a player types, for example `open the door`,
`e` or `og, get donuts`. Then read the result. **Why?** asks the engine why the
last turn had its result. A refusal such as *You can't open the case: the case is
locked* is already the reason that the engine gives, in words.

You do not need a key for a language model, because the command templates of the
story are the grammar. An API key lets the editor use the language model of a
different company (Misc ▸ API keys). When a key is set, the editor sends to the
model each line that the story cannot understand. It also sends the commands that
the story can accept. The model then selects one of these commands, or none of them:

- If the model selects a command, the game plays the command as if you typed it.
  The words *I take that as: …* come before the command.
- If the model selects no command, it says *I really don't understand that*.

While the model works, the input box shows *let me see if I understand…*.

The **each turn** box next to Commands shows the commands that operate after each
turn. The games list moves between a game and the games forked from it. A forked
game is a copy of a game that continues separately. The last item of the list,
**Fork this game…**, starts a second game from your exact position. **Diff**
operates only on a forked game. It tells what happened in this game and not in the
game that it was forked from.

**The left column** is your program. It has one tab for each open file, and the
text of the file.

**The right column** shows the run of the tab that is bright, in six different
ways. Before the first run, the right column tells you what to do. It also shows
the buttons that do it.

| region | what it is |
|---|---|
| **file tabs** | One tab for each open file. A tab keeps its own *run* and its own text. |
| **the editor** | One set of colour rules for LPS and for the Prolog in it. |
| **the panes** | Six views of the run of the bright tab. |
| **Assistant** | A language model with the same tools as you. It is closed until you open it. |
| **Live** | A program that continues its cycles and accepts events. It is closed until you open it. |

You can change the size of each part. The editor keeps the sizes for your next
visit. Drag the vertical bar between the editor and the panes. Double-click that
bar to put it back in the middle. When a panel is open, drag the horizontal bar
above it.

**Each tab has its own run.** Open two programs and run the two programs. When you
change to the other tab, all of the right column changes: the timeline, the scene,
the cycle and the errors. A tab with a program that ran has a green dot. To compare
two versions of a program, do these steps:

1. Open the two versions.
2. Run the two versions.
3. Change between the two tabs.

## Running a program

**Run** compiles the program and runs it to the end. Ctrl/Cmd + . runs one more
cycle of the current run. **Run one more cycle** in the right-click menu of the
editor does the same. Thus you can continue a run without a new start.

The status line tells how far the run went *and why it stopped there*. An example
is `success after 21 cycles · reached maxTime(20) · 34 ms`. These are two
different facts. A run that reached `maxTime` reports success. A run that had no
more work to do also reports success. Only the second run is really complete.

The **maxTime** box replaces the value of the program, for the next run only. Your
file does not change. To use the value of the program, keep the box empty.

**The scenario picker.** A scenario is a list of events, each with its time. A
Logical English document writes a scenario as `scenario one is:`. A document can
have more than one scenario. Thus you can try the same rules on different
histories. But a run observes only one scenario.

When the document has more than one scenario, a list shows next to **Run**. The
list gives the name of each scenario, in the order of the document. At the start,
the first scenario is selected. To use a different scenario, do these steps:

1. Select the scenario in the list.
2. Click **Run**.

The run observes the events of the scenario that you selected. The tab of the
document keeps your selection while the tab is open. On the command line,
`./lps run DOCUMENT.le --scenario NAME` does the same.

When a run is complete, the panes show the last cycle that has a recorded state.
This is not cycle 0, which is the start state of the program. It is also not the
last time value of the engine. That value is one cycle after the last cycle in
which something happened.

Next to the cycle slider are ⏮ ◀ ▶ ▶| ⏭: first, back, play, forward, last. The
arrow keys, Home, End and the space bar do the same. They operate from all
locations outside a text box.

## The editor itself

The editor shows fluents, events and actions **in colours, in agreement with the
declarations of the program**. A fluent is dark text on a pale blue background. An
event or an action is amber. These are the colours of LPS1, from its own style
sheet. Thus a program looks the same here as in SWISH.

A colour rule that uses only the shape of the text cannot do this.
`loc(wolf,north)` and `row(south,north)` have the same shape. Only the declarations
tell which of the two is a fluent. The colours follow the meaning that the editor
found in the program. Thus, when you add a name to a `fluents` declaration, all
uses of that name immediately change colour.

The clauses that fired in the last run have a mark in the margin. A rule that never
fires is the most usual mistake in a first LPS program. Nothing else shows this
mistake: the program runs, but it does nothing.

Put the mouse pointer on a name, and the editor tells you what the name is. An
example is *a fluent this program declares*. It also tells how many arguments the
name has. Put the mouse pointer on an operator, and the editor shows the data
about that operator in the table of operators.

The editor shows mistakes **in the text**, not in a separate area below the text.
A mistake gets these marks:

- A wavy line below the line.
- The message, when you put the mouse pointer on the wavy line.
- A mark on the right edge of the scrollbar.

The count in the top bar is a button. Click it to go to the first problem. Push
**F8** to go to the next problem.

![A program that does not parse](../images/ide-diagnostics.png)

The editor examines the program approximately one second after you stop typing.
The server does the examination, and it reports exactly what the compiler reports.
Sometimes the server cannot read a file to the end. The server then reports all
that it found before it stopped.

**Right-click** in the text to see a menu:

| item | |
|---|---|
| Run | Compile and run. This is the same as Ctrl/Cmd + Enter. |
| See PROLOG | Shows the clauses that the sentence at the cursor makes, in the internal syntax that the engine runs. A small window shows the clauses, and you can copy them. The Logical English editor has the same command. On an empty line or a comment, it tells you that there is nothing to show. |
| See internal syntax | Shows all of the program as the engine runs it, in the Internal pane. |
| Why did this happen? | Explains the term at the cursor, at the current cycle. |
| Observe this (live session) | Sends the term at the cursor as an event to a running session. |
| Show definition | Goes to the first clause with that name. On a Logical English `includes these resources:` line, it opens the resource at the cursor. A local document opens in its own tab. A URL opens in a new window. |
| Go back | Goes back to the previous location. |
| Show occurrences | Shows each use of the name, in a list. You can click each item of the list. |
| Fold / unfold all clauses for this predicate | |
| Copy URL | Copies a link that contains the program. |

The same menu has cut, copy and paste. It also has all the functions of the text
editor below it: **Ctrl/Cmd + F** to find, **Ctrl/Cmd + H** to replace, more than
one cursor at the same time, line moves, and comments. When you select a term, the
editor highlights its other occurrences. When the cursor is on a name, the editor
does the same.

While you type, the editor shows possible completions. These are the words of the
language *and* the words of this program. The words of the program are the events
and actions that the program declares, from the last examination by the server.

## The six panes

Five of the six panes move together with one cycle slider. The slider shows when
there is a run, and it is not there when there is no run. Below the slider, a mark
shows each cycle in which something changed. Thus you do not have to drag through a
run with few changes. Click a mark to go to that cycle.

**The meaning of the row of tab names.** A tab can be dim for one of two reasons.
Put the mouse pointer on the tab to see the reason:

- *"run the program first"*: the tab will fill when you click Run.
- *"this program declares no display/2 clauses"*: the tab will not fill when you
  click Run, at any time. The empty pane shows the button that can change this.

A tab that is not dim has contents now.

Two more marks can show in the area above the panes. **LIVE** means that the panes
follow a running session, not the last click on Run. *"was run before your last
edit"* means that you typed something after the run that the panes show.

**If you keep the page open for a long time**, the server can possibly stop before
the run of the panes. A server on the internet stops its computer when it gets no
requests. Each run, and all the data that the panes read from a run, is in the
memory of that computer. You do not have to do anything. Your next click shows
*"the server restarted — running again…"*. The editor runs the program in the
editor again. The pane that you asked for comes back, at the same cycle.

### Timeline

The timeline has one row for each fluent, with a bar for the time that the fluent
is true. Below these rows are the events of each cycle. Then there is a row for
composite events. A composite event is an event that other events make. This row
shows only if the program has composite events. Click the picture to go to that
cycle.

A fluent can have a default value (`defaults/1`, or `; 0 by default` in Logical
English). Such a fluent has one dashed *every other: …* line next to the rows of
the stored entries. Each key with no row of its own has the default value. An
observed event that a constraint refused shows crossed out in red (refer to
[Asking why](#asking-why)).

![The timeline](../images/ide-timeline.png)

### Changes

This pane shows what started, stopped and changed at this cycle. The items are in
groups, under *the causal law that caused them*. Click the law to go to that
clause.

The pane shows the items that did not change in a separate list, as *persisted*.
The reason is that the engine knows the difference between "still true" and "made
true again". If nothing changed at this cycle, the pane shows the nearest cycle in
each direction where something changed.

If nothing changed in *any* cycle, the pane tells you this, and it tells you why.
Some programs change their fluents only when an event comes in. Such a program does
nothing in a usual run. It needs a session that does not stop, not one more click
on Run. `lights.lps` and `thermostat.lps` are two programs of that kind.

![Changes](../images/ide-changes.png)

### Automaton

This pane shows the run as a diagram of its states and the steps between them.
Each different state shows one time. Thus, when a program goes back to an earlier
state, the diagram shows a loop. When the states of a run make a simple chain, the
diagram is a column. When a run has branches, the diagram goes from left to right.

The pane has two switches:

- *abstract numbers* merges the states that are different only in a number.
- *hide self-loops* removes the arrows from a state to the same state.

![The state-transition diagram](../images/ide-automaton.png)

Click a state to move the cycle slider to that state.

### 2D

This pane shows the picture that the `display/2` clauses of the program describe.
The point [0, 0] is at the bottom left, and y increases upwards. Use the mouse
wheel to zoom in and out. Drag to move the picture. Double-click to fit all of the
picture into the pane.

Put the mouse pointer on an object, and the pane gives the name of the fluent of
that object, and the cycle. A key in the corner gives the colours. These controls
are at the bottom:

- **Scenes** shows all of the run as a strip. The next section describes it.
- **PNG** saves the picture on the screen as an image file.
- **Record** plays the run and records it as a video file.
- **Compare** puts this cycle next to the cycle before it.
- **◀ change** / **change ▶** go to the cycles where the picture *becomes a
  different picture*.

For example, an eight-cycle run of the Underground notice has four such cycles,
but the slider has eight cycles. The marks below the slider are the same cycles. An
amber mark is a state that the run had before.

#### One picture, or the whole run: **Scenes**

The **Scenes** button is in the row of controls of the pane. View ▸ *Split the run
into scenes* does the same. The button changes what the 2D and 3D panes show:

- When Scenes is off, the pane shows one picture. You move through the run with the
  slider.
- When Scenes is on, the pane shows the run as a **strip**. The strip has one
  picture for each time that the picture changed, in order. Between the pictures,
  the strip tells what moved the story forward. Below each picture, it tells what
  started, stopped or changed value.

The strip answers the question "what happened?". The single picture answers the
question "what is true now?". The strip has its own controls. **◀ Single scene**
goes back to the single picture. **PNG** saves all of the strip as one image.

Click a picture of the strip, and the full picture at that cycle opens. The strip
is the map, and the single picture is one place on the map. The first button then
shows **◀ Scenes**. This button goes back to the strip, at the position where you
left it. The editor keeps your selection (strip or single picture) for the next
program. A live session always shows the single picture. The reason is that the
run is not complete, thus there is no full run to show.

If the program is a Logical English document, all the text is in **the words of
the document**. This includes the captions, the lines between the pictures, the
key and the messages that show when you put the mouse pointer on an item. For
example, a document can declare
`*a payer* transfers *an amount* to *a payee*; known as transfer`. The pane then
shows *"fariba transfers 10 to bob"*, not `transfer(fariba,10,bob)`. A term that
has no template shows as a term.

### 3D

This pane shows the picture that `display3d/2` describes. Drag to turn the scene.
Use the mouse wheel to move nearer to the scene or farther from it. Push ⤢ to fit
all of the scene into the pane.

When you move the cycle slider, your view does not change. A camera that the
program declares sets only your *start* position. It is not an instruction for
each picture.

**Scenes** also operates here. The strip is then a row of pictures of the scene,
one for each time that the scene changed. The same functions make these pictures.
Each picture shows all of its contents, but not from the camera of the program. The
program selected that camera for a pane of full size.

**While a session runs, the 2D and 3D panes follow the session**, not the last
complete run. A click in one of these two panes goes to the program. A separate
window (popped out) does the same.

### Internal

This pane shows the form that the engine runs: `reactive_rule/2`, `d_pre/1`,
`updated/4`, `initial_state/1`. Look at this pane one time. It shows that
`false X, Y, Z` is a constraint. It also shows that `at`, `from` and `to` are an
easy way to write a time as one more argument of a relation.

**Copy this text** copies all of the text. A report of a fault needs all of the
text. Click a line, and the editor looks for that predicate in your program.

## Asking why

There is no pane for explanations. **Right-click an item that a pane shows**, and
the explanation for that term at that cycle shows. The item can be a bar on the
timeline, an event, a row of the changes table, a state, the label on an arrow, a
shape in two dimensions, or a solid in three dimensions.

The dialog also has a **why not** box. Frequently the important question is about
something that is *missing*. You cannot click something that the pane never showed.
The box already contains a question of the correct shape. Do these steps:

1. Edit the question.
2. Click the button.

The forms of question that the box accepts are below the box.

The dialog keeps your earlier questions. Thus, when you ask a new question, the
answer that you read stays. **Copy** copies the question and its answer together.
The cycle box asks the same question at a different cycle, and the dialog stays
open. *Why not earlier?* asks the question about the cycle before.

Each part of the answer that gives the name of a clause is a link into the editor.
The link selects all of the clause, not only the first line of the clause.

`why_not` has six different answers. Each answer has a different meaning:

- **scheduled_for_another_cycle**: the plan will do it, but later, as step *n*.
- **no_goal_created**: nothing asked for it.
- **refused_by_constraint**: the event was *observed*. This means that it was a call
  from outside: from the scenario of the program, or as a live observation. An
  integrity constraint was true in the state when the call came in. Thus the
  engine refused all of the call. The answer gives the name of the constraint, and
  the values that made the constraint true. The timeline also shows such a call,
  crossed out in red. In a contract, the same thing is a revert.
- **blocked_by_denial**: something asked for it. A constraint with a name, on the
  state at the start of the event, prohibited it.
- **rejected_by_prospective_constraint**: something asked for it. A constraint with
  a name, on the state that the event would make, refused it.
- **no_plan_found**: something asked for it. The engine found no plan within the
  distance that it looks forward.

A question about a fluent, `why_not(holds(F), T)`, has its own answers:

- The fluent is true.
- The fluent was true, and then an event terminated it. The answer gives the event
  and the law.
- The fluent was never true. The answer gives a list of the causal laws that could
  make it true.

An *intensional* fluent is a fluent that a rule calculates from other fluents. In
Logical English, it is a sentence that ends `at a time if …`. The engine never
stores such a fluent. Thus the answer calculates it again from the state that the
run recorded for that cycle. *Why* gives the name of the rule and shows each of its
conditions, with the values that made the condition true.

*Why not* gives a list of the rules that can give the fluent. For each rule, it
shows the conditions that are true and the first condition that is false. When that
condition is also a fluent, the answer explains that condition too. A comparison
that is false shows with its values, for example `7=<5`.

For all other questions, the answer is "no applicable rule". When the record of the
run has no data, the answer is *not recorded*. The answer does not give a possible
story that the system made after the run. When something is wrong, this is the
most important property of the feature.

## Logical English

A `.le` file opens here the same as each other file. All the functions to the right
of the vertical bar operate on a `.le` file without change. You can run it, move
through the cycles, ask why, and show it as a picture.

![Logical English, edited and run here](../images/ide-le.png)

The difference is in the left column.

- **The colours come from the list of words of LE2 (Logical English, version 2).**
  The section headings, the joining words and the `*slots*` get their colours from
  the LE2 file `i18n/keywords.csv`. The editor reads this file when it starts. It
  does not keep its own copy. A copy would become incorrect for all languages
  except English when one of the two systems changes.
- **The completions come from the templates of the document.** Each completion has
  a label that tells its function. Two templates that are similar can be one fluent
  and one action. An author must know first which is which.
- **The editor shows errors on the English line.** The errors of LE2 and the errors
  of LPS2 show one after the other, and never mixed. The reason is that they are
  different claims about different texts. The two kinds of error show on the line
  of the `.le` file. Each term that the translation makes keeps the sentence that
  it came from.
- **The generated program is next to the document.** The Internal pane shows the
  result of the compilation of your English. You cannot edit that pane. Each line
  of the pane has a link back to the sentence that made the line. Click a term to
  go to that sentence.
- **Prolog goes in the companion file.** `badlight.le` and `badlight.lps` are one
  program. The English tells what is true and what happens. The `.lps` part holds
  the text that is not English, and that has no advantage when written as English.
  The most important example is the drawing clauses. When you open one part, the
  other part also opens. The two parts compile, run and show together. Each part
  keeps its own colours and its own errors. Thus a mistake in the companion has its
  mark in the companion. When you click Run in either tab, all of the program runs.
- **Edit ▸ Say it in English…** changes a sentence into Logical English. It uses
  only the templates that this document declares. It examines the result against
  the program, makes the result better, and shows it to you. Nothing goes into your
  document until you tell the editor to put it there.

LE2 reads the English. LE2 has the grammar, the dictionary and the part that
writes English back. LPS2 loads LE2 as a library. Thus the translation of a
document is one predicate call in the same program. It is not a request across the
network. Start the server with a copy of LE2 that it can load:

```sh
LPS_LE2_LIB=/path/to/LogicalEnglish2 ./lps ide
```

Two other settings do the same task. `LPS_LE2_URL` gives the URL (web address) of
an LE2 server that already runs. `LPS_LE2_DIR` gives the location of a copy of LE2
on this computer. The server loads it in the same way. If `LPS_LE2_SUBPROCESS=1` is
also set, the server runs it as a separate program.

**When none of the three settings is set, there is no Logical English.** A `.le`
file still opens, and it tells you which setting to give. Nothing else in the
editor changes. The editor never guesses which copy of LE2 to use. The reason is
that a `.le` file that the incorrect copy compiles is a program with a meaning that
nobody stated.

## The assistant

The assistant is a language model with the same tools as you. The assistant
compiles, runs, asks why, and examines the result of its own drawing clauses. The
assistant and the editor have the same idea of "this compiles", because both use
the same call.

For a program in the LPS notation, the assistant reads the LPS language reference.
For a Logical English document, it reads the Logical English references:

- The reference about the shape of a document for LPS.
- The Logical English language reference, with its advice about how to write good
  Logical English. The assistants of the Logical English editor read the same
  reference.

To open the assistant, select **View ▸ Assistant panel**. To use a model for one
question, select the model at the top of the panel. To set the model that you
usually use, select **Misc ▸ API keys, models & Assistant settings**.

The list of models is the list that the providers give. The server reads the list
when it starts. It reads the list again when you click *Re-read from providers*. A
key that you type in the browser is preferred to a key of the server. When there is
no key, the panel tells you this and shows the button that sets a key.

The server pays for the requests that use its own keys. Thus these requests have a
limit, the same limit as the tools for other assistants
([LPS2 over MCP](../api/mcp.md#limits-and-keys)). Without a sign-in, each IDE has 10
units in a minute and 200 units in a day; all the IDEs at one internet address have,
together, ten times that. A request to the assistant, or a story, uses 10 units; a
sentence translated to Logical English uses 3 units. When a request is over the
limit, the assistant tells you how long to wait. **With your own key for the
provider of the model, there is no limit.**

The public server also has a budget for running programs, so that one person
cannot keep it busy for everybody. A run uses one unit for each second that it
takes. A step of a program takes only a fraction of a second, so to step through a
program uses almost nothing. A program that loops until its time limit uses 30
units. You can have two programs running at the same time. When you are over the
limit, the IDE tells you how long to wait. A server on your own computer has no
limit.

You can also ask the assistant about LPS, or about the IDE. The IDE (integrated
development environment) is the editor and all the parts around it. An example
question is *How do I observe an event in a live session?* The assistant searches
this documentation for your question and gives a short answer. At the end, it gives
a maximum of three links to the sections that tell more. These links open in a new
browser tab. The server does the search before the model sees your question. The
model can search again with different words. A request to change the program gets
no links.

Two buttons ask a question that is already written.

**Animate in 2D** asks the model for a *plan*. The plan tells which containers
there are, and what moves between them. It tells which fluent puts a thing in a
container, and what each thing looks like. The editor then calculates the positions
and the sizes. The model never writes a coordinate. Thus nothing in the result
overlaps:

![Animate in 2D](../images/ide-assistant-2d.png)

The result is usual Prolog clauses on a table of positions, `lps_slot/4`. When you
move a position in the table, all the things at that position move with it.

**Animate in 3D** asks for the same plan, and shows it in three dimensions. The
grid of containers becomes a floor plan. Things stand up from the floor. A stack
becomes a tower.

Nothing goes into your file until you click **Apply to editor**. One undo removes
it again.

For a Logical English document, the clauses go into its `.lps` companion. If there
is no companion, the editor makes one and opens it. The clauses are Prolog. Prolog
in an English document is not only a bad edit, it is an impossible edit. LE2 reads
a clause as an incorrect section, and the document stops compiling.

## Sessions that do not stop

If you remove `maxTime`, a program runs until you stop it. It does nothing until an
event comes in. To open the **Live** panel, click it in the top bar.

![A session that does not stop](../images/ide-live.png)

When no session runs, the panel shows only a rate and a Start button. The other
controls show when there is a session for them.

- **every N ms**: the time for each cycle. The engine still calculates its own time
  from the cycle number. This setting sets only the speed from one cycle to the
  next.
- **Send**: sends an event term. The menu next to Send shows the events that *this*
  program declares. Select one, and the editor fills the box and selects the
  arguments. Put the mouse pointer on that menu to see if the program accepts mouse
  events.
- **quiet cycles**: also record the cycles in which nothing happened. This setting
  is off at the start. At two cycles each second, "nothing happened" would be most
  of the text.
- **Save log**: writes all of the record to a file. You cannot repeat a session that
  runs in real time in a different way.
- **Translate**: say what you want in English, and the assistant selects the term.
  The editor shows you the term before it sends the term. The reason is that an
  incorrect translation gives an event that you did not want.
- **Pop out 2D / Pop out 3D**: opens a window that follows the running session.
  These two buttons show only for a program that has something to show as a picture.

The record has one line for each cycle in which something happened. The line shows
the observed events, the actions, and the fluents that started (`+`), stopped (`-`)
or changed value (`→`). The heading gives the number of cycles and the time since
the start. When the session cannot keep the rate that you asked for, the heading
also gives the real rate.

An event that comes in during a cycle goes to the start of the next cycle. The
record shows *queued for cycle N*. Thus you know in which cycle to look for that
event.

**You can click a program that declares `lps_mousedown/3`, `lps_mouseup/3` or
`lps_mousedrag/3` as events.** The separate windows send those events in the
coordinates of the program. The editor does not send clicks to a program that
declares none of the three. `examples/start/lights.lps` is the demonstration.

## The menus

Put the mouse pointer on a menu item, and it tells you what it does. Sometimes an
item needs something that the file on the screen or the server does not have. Such
an item is grey. Put the mouse pointer on the item to see why.

**File** has these items:

- *New LPS program* (`.lps`, the written form).
- *New Logical English program* (`.le`). This is a small Logical English for LPS
  program to start from. It has an action, a fluent, a causal law, a constraint and
  a scenario. The item is grey when this server has no LE2.
- Open, which opens more than one file at the same time.
- Open example from server. This item shows all the programs on the server in a
  tree of folders. The tree contains the LPS2 programs, the Migration twins with
  one folder for each source system and twin, and the collection of LPS1 programs.
  It has a search box and a name column that you can make wider.
- Save, Save As, Close file and Copy share link.

To use the search box, type some words, or a phrase in quotation marks. Each word
must be in the program. Then select where to look in the list next to the box:

- **everywhere** (the default).
- **in names**: the name of the program and its first comment.
- **in declarations**: the `fluents`, `events` and `actions` of an LPS program, or
  the templates and the other declaration sections of a Logical English document.
- **in the text**.

While you type, the editor filters the tree by name. After a short time, the server
gives the programs that match, with the best match first. Each program shows the
line that matched. A name match is better than a declaration match, and a
declaration match is better than a match in the text. To select a program and see
its first lines, click it, or use the arrow keys. To open the program, double-click
it, push Enter, or click the *Open* button.

`.pddl` and `.drl` files open the same as other files. The server translates them
into LPS. The tab has a note that tells what the program was translated from, and
when. Select the files that are related together: a PDDL domain with its problem,
or a `.drl` file with its `.wording` file. An Inform 7 story (`.ni`) opens as the
Logical English story that its assertions make.

When Logical English is loaded (`LPS_LE2_LIB`), File ▸ Open also accepts all the
kinds of file that the Logical English installation can read. Examples are a
Solidity contract, a Miniscript policy, a zip file of a project, and the other
systems on its list of formats (operation `import_formats`). File ▸ Open opens such
a file as a Logical English document. Put the mouse pointer on the menu item to see
the list of formats that this server can change. The notes from a conversion are a
comment at the top of the document.

**Edit** has these items: undo and redo, find, replace, go to line, comments on one
line and on a block, collapse all clauses, expand all clauses, and next problem. It
also has **Insert a construct…**. This item shows the shapes of rule. Use it when
you know what you want to say, but not which word says it. For a Logical English
document, Edit also has **Say it in English…**.

**View** has these items: the original file of a translated file, and the *legal
view* of a Logical English LPS document. It also has a comparison of this run with
the previous run, and a pane of documentation next to the editor. Last, it has the
two optional panels: the assistant and the live session.

The legal view comes from the LE2 file `le_lps_legal.pl` (operation
`le_legal_view`). It changes the integrity constraints of the document into one
rule for each action. Each such rule tells who can do that action. It also changes
the causal laws of the document into rules about effects. Examples are *a sender
may transfer an amount to a recipient if …* and *a sender transferring … results in
the balance of … being …*. The result is a Logical English program that has no
time in it. It opens in its own tab.

The editor makes the legal view again each time, from the document and from its
run. Thus this server runs the program first. The view has a scenario with the
state just before each call of the scenario of the document. It also has two
questions:

- Can the call be made? The expected answer is yes exactly when the run accepted
  the call.
- What does the call change?

You can ask the view these questions: can this call happen? what does it change?
what must change to allow it? The LE2 editor answers these questions, not this
engine. The menu item is grey unless the file on the screen is a Logical English
document that declares `the target language is: lps.`

**The original this was converted from** shows the file that a program came from.
This is one of two things:

- The file that the editor converted when you opened it. Examples are a Solidity
  contract, a PDDL or Drools file, or an Inform story.
- For a program that you opened from the server, the files in the `sources/` folder
  next to it. The LE2 migrations keep in that folder the original of each twin.

The original opens in its own window. The title of the window is "Original that
was converted into", followed by the file name of the program. Thus you can read
the two files side by side. If the browser blocks the new window, a dialog shows
the original.

**Misc** has these items: the theme (dark, light, high contrast), the font size,
the API keys and models for the language models, and the access token of the
server. It also has *Deploy as WASM*, *Deploy as Solidity* and *Export to another
system*.

**Export to another system…** writes a Logical English document in the format of a
different system. It uses one of the writers of the Logical English installation.
The LE2 list of writers is in `le_import.pl`, and the editor uses it through
`le_service:le_export/4` (operations `export_formats` and `export`). The menu shows
only the writers that can write this document. The dialog shows the result with
**Copy**, **Save…**, and one button for each public site where you can try the
result. The writer gives these sites. For example, a Miniscript policy opens in
Minsc.

**Deploy as Solidity…** writes the program in the editor as a Solidity contract. The
program can be LPS, or Logical English for LPS. The operation is `to_solidity`, and
the command line is `lps solidity FILE`. The translator for this menu item is
`lps_solidity.pl`. It is one of the two translators that this server loads from the
private lpsPlus collection of files (`src/syntax/lps_plus.pl`). If the server does
not have these files, the menu item is not available, and it tells you this. Nothing
else in the editor changes.

The translation obeys fixed rules:

- Each fluent becomes state: a mapping from its keys to its value. A `has…` flag is
  next to the mapping, because a fluent can be *absent* and a mapping cannot.
- A fluent with a default, `; 0 by default`, is the exception. Such a default is
  exactly the zero of a mapping. Thus that fluent gets only the mapping.
- A named constant becomes a Solidity `constant`.
- Each action becomes a function. When the first argument of that function is a
  person, the argument is `msg.sender`.
- Each integrity constraint on an action becomes a `revert` at the start of the
  call. A constraint on the state after the call becomes a `revert` at the end of
  the call.
- Each causal law becomes a write to the state, in the order of LPS2. First, the
  conditions of all the laws are read on the state before the call. Then come the
  fluents that stop, then the fluents that start, then the updates.
- The parameters have the addresses first and the values after. This is the
  convention of Solidity: `transfer(to, value)` keeps the ERC-20 selector, but the
  sentence is "a sender transfers an amount to a recipient". The events give their
  arguments in the same order.
- The public getters have the names of the fluents (`balance`, not `balanceOf`), as
  the dialog tells.
- `initially` becomes the constructor. The parameters of the constructor are the
  accounts that the program names (`alice`, `the owner`). The reason is that a
  program cannot know their addresses.
- The scenario of the program is at the top, as the calls to make.
- A Logical English document gives the names of the functions and the parameters.
  It also gives each line its own sentence as a comment.

The dialog shows the source, with **Copy source** and **Open in Remix IDE**. Remix
([Remix](https://app.remix.live)) is the public editor of the Ethereum Foundation,
and it runs in a browser. The source goes in the address (`#code=<base64>`). Remix
compiles it in a separate workspace. *Deploy & run ▸ Remix VM* puts it on a chain
in the page, with test accounts that already have money. You do not have to
install anything, and you do not need a wallet.

**For some programs there is no direct translation. The translator refuses such a
program, and it does not give an approximate translation.** The dialog gives each
reason, with a link to its line. These are the reasons:

- A reactive rule. A contract does nothing by itself; it only answers calls.
- An intensional fluent or a composite event.
- Planning.
- An event that the outside world observes, not an action that a person calls.
- A constraint on two actions at the same time.
- A timeless rule. But the translator writes timeless *facts*, as lookups.
- The Prolog of the program.
- A fraction (`/`). The EVM (Ethereum Virtual Machine) has only whole numbers, thus
  write `//`.
- A read that must search a mapping. This is a set fluent with an argument that is
  not yet known.
- A fluent that the program lets have two values for one key.

The lpsPlus file `migration/solidity/lps_solidity_test.pl` keeps these rules
correct. It examines the refusals. It also examines the Solidity twins of lpsPlus:
ERC-20, Ownable, Pausable, the three together, and the FiatToken of Circle. For
these twins, it makes sure that the contracts compile without a warning. It also
makes sure that, when an EVM runs them again with the scenario of the program, they
end in the same state as the LPS2 run.

**Help** has these items: the start page, the keyboard shortcuts, this document,
the tutorial, the language reference, the glossary, and the tour. It also has the
map of the other systems that LPS2 reads and writes
([other systems](../integrations/index.md)), and **Search the documentation…**.
Last, it has the licences of the icons, and About. About tells which build you use.

The search looks in the text of all the documents. All the words that you type must
be in one section. A phrase in quotation marks must be there exactly as you wrote
it. The results are in groups by document, with the best result first, and always
in the same order. Each document has a search box at its top, and the start page
also has one.

**Documentation for this**, in the right-click menu of the editor, searches for
what the word at the cursor *is*. Some examples:

- A variable finds the documentation about variables.
- A name that the program declares as a fluent finds the documentation about
  fluents.
- `initiates` finds that keyword.
- A date finds the documentation about dates.

---

## How do I …

**…run a program?** Push Ctrl/Cmd + Enter, or click the Run button. The panes fill.

**…see why something happened?** Right-click the thing, in any pane.

**…see why something *did not* happen?** Right-click an item. Then edit the
*why not* box in the dialog.

**…compare two programs?** Do these steps:

1. Open the two programs. File ▸ Open accepts more than one file at the same time.
   You can also use the + on the row of tabs.
2. Run the two programs.
3. Change between the tabs.

Each tab keeps its own run.

**…find where a predicate is defined?** Right-click it and select Show definition,
or push Ctrl/Cmd + F12. *Go back* takes you back. In a Logical English
`includes these resources:` line, the same action opens the resource. A document on
this computer (`world` in a story) opens in a tab, together with its companion. A
URL opens in a new window.

**…give my program an animation?** Open View ▸ Assistant panel and click
*Animate in 2D*. You can also write the `display/2` clauses yourself.
[`lps.md`](../reference/lps.md) §18 gives a list of the properties.

**…use one of the built-in pictures?** Write `[type:raster, icon:NAME]`.
Help ▸ About the icons, fills and objects gives a list of all the names, with their
pictures.

**…fill a shape with something that is not a colour?** Write `pattern:NAME`. The
patterns are `hatch`, `bricks`, `waves` and sixteen others, in two dimensions and
three dimensions. The same dialog gives a list of them.

**…make a 3D scene from things, not boxes?** Write `[type:model, model:NAME]`. The
models are `person`, `tree`, `house`, `truck` and thirty others. The same dialog
gives a list of them.

**…see all of the run, not only one cycle?** Click *Scenes* in the toolbar of the
2D or 3D pane (or select View ▸ *Split the run into scenes*).

**…send events to a program while it runs?** Do these steps:

1. Open the Live panel.
2. Click Start.
3. Type an event term. Or say it in English and click Translate.

**…make an animation respond to clicks?** Do these steps:

1. Declare `lps_mousedown/3` as an event. If you want them, also declare
   `lps_mouseup/3` and `lps_mousedrag/3` as events.
2. Write a rule that reacts to those events.
3. Pop out the 2D window.
4. Click in the window.

Refer to `examples/start/lights.lps`.

**…run a PDDL problem?** Select File ▸ Open, and select the domain *and* the
problem together. The two files open as one LPS program with `achieve` at the end.

**…run a set of Drools rules?** Do these steps:

1. Select File ▸ Open, and open the `.drl` file.
2. Add an `initially` line to put some facts into the working memory. The note at
   the top of the generated program also tells you this.
3. Run the program.

**…see the original text of a translated file?** Select View ▸ The original this
was converted from.

**…see what changed between two runs?** Do these steps:

1. Run the program.
2. Edit the program.
3. Run the program again.
4. Select View ▸ Compare with the previous run.

The cycles that are different are highlighted.

**…get my unsaved work back after I load the page again?** Your work is already
there. This browser keeps the files with unsaved changes, and shows them again on
your next visit.

**…write my program in English?** This is Logical English. Do these steps:

1. Start the server with `LPS_LE2_LIB=/path/to/LogicalEnglish2`.
2. Put `the target language is: lps.` at the top of a `.le` file.
3. Edit the file here.

You do not have to run a second server. Refer to [Logical English](#logical-english).

**…share a program?** Select File ▸ Copy share link. The program goes in the
address. Thus nothing goes to a server.

**…run a program with no server?** Select Misc ▸ Deploy as WASM. WASM is short for
WebAssembly, a way to run the engine in the browser. You get a single HTML page (a
usual web page) that contains the engine and your program. The dialog tells what
the page still gets from other locations, and how to serve the page.

**…use an editor from a server that needs a token?** Open the editor one time as
`…/ide?token=<the token>`. This browser keeps the token, and the editor removes it
from the address bar. You can also set the token in **Misc ▸ Server token…**. If
you do neither, the first request to the server opens that dialog. The dialog tells
which operation the server refused. On such a server, *nothing* operates without
the token, because each task of the editor is a request to the server.

**…use the editor with a different LPS2 server?** Set `window.LPS_API_BASE` before
the page loads its script. Or serve the page from that server. The LE2 editor uses
`?lpsapi=…` in the address for the same purpose.

**…remove the "this needs a key" message of the assistant?** Select Misc ▸ API
keys. Or start the server with `ANTHROPIC_API_KEY`, `OPENAI_API_KEY`,
`GROQ_API_KEY`, `GEMINI_API_KEY` or `TOGETHER_API_KEY` set where the server can see
it. The server prefers such a key to a key that you type in the browser.

**…stop the reset of the 3D scene when I move the slider?** The scene does not
reset now. To go back to the camera of the program, push ⤢.

**…read the error messages, now that there is no separate area for them?** The
messages are on the line. Put the mouse pointer on the line to see the message.
Push F8 to go through the messages. Click the count in the top bar to go to the
first message.

---

## Keyboard shortcuts

| | |
|---|---|
| Ctrl/Cmd + Enter | run |
| Ctrl/Cmd + . | run one more cycle |
| ← → | previous / next cycle |
| Home / End | first / last cycle |
| space | play or pause |
| Ctrl/Cmd + F | find |
| Ctrl/Cmd + H | replace |
| F8 | next problem |
| Ctrl/Cmd + F12 | show definition |
| Ctrl/Cmd + / | add or remove a comment on the line |
| Alt + ↑/↓ | move the line up or down |
| Shift + Alt + ↑/↓ | duplicate the line |
| Ctrl/Cmd + D | select the next occurrence |
| Escape | close a dialog |
| Middle-click a tab | close that file |

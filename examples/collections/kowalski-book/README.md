# Kowalski's book — the chapters on time, agents and the event calculus, in LPS

Twelve examples from Robert Kowalski's book *Computational Logic and Human
Thinking* (Cambridge University Press, 2011): the chapters in which an agent
acts over time. Each example is here twice: `<name>.lps` in the older,
Prolog-like syntax, and `<name>.le`, the same program written in Logical
English. The two run alike.

## Start here
- [The London Underground notice](underground.lps): the book's first
  example. A notice read as goals and rules drives an agent. Its
  [Logical English version](underground.le) reads like the notice.
- [The runaway trolley](trolley.lps): a moral constraint that stops an
  action.
- [The fox and the crow](fox_crow.lps): a story with goals, actions and a
  crow that learns.
- [The event calculus](event_calculus.lps): the book's calculus of events,
  which LPS makes almost trivial.

## Try this
1. Open [the Underground notice](underground.lps) and press **Run**. On the
   **Timeline**, the fire is observed, the alarm is pressed and the train stops.
2. Open [its Logical English version](underground.le) in a second tab and
   run it too. Switch between the two tabs: the runs are the same.
3. Open [the trolley](trolley.lps) and press **Run**. The trolley goes onto
   the side track, and the bystander is never pushed.
4. Right-click anything on the timeline, and ask in the **why not** box:
   `why_not(happened(push(bystander)), 2)`. The answer is
   *blocked_by_denial*, and it names the rule that forbids the push.

## More
- [Details](DETAILS.md): which chapter each program comes from, and which
  examples of the book LPS cannot express, and why.
- [Logical English for LPS](/docs/user/reference/le-for-lps): the language of
  the `.le` versions.

# Planning — PDDL problems, solved by LPS2's planner

Classical planning problems written in PDDL, the Planning Domain Definition
Language: blocks, gripper, towers of Hanoi, logistics, an elevator, a rover
and lights. Each problem is one file, and its domain is another. LPS2 turns
the pair into an LPS program when it opens the problem, and plans with its own
planner.

## Start here
- [Blocks, problem 1](blocks-p1.pddl): four blocks on a table, to be stacked
  into one tower.
- [Towers of Hanoi, problem 1](hanoi-p1.pddl): the classic puzzle.
- [Lights, problem 1](lights-p1.pddl): a domain that uses types, `or`,
  conditions on every object, and effects that depend on the state.

## Try this
1. Open [blocks, problem 1](blocks-p1.pddl). The editor shows the LPS program
   written from it, with a note saying which two files it came from.
2. Press **Run**. On the **Timeline**, one action runs in each cycle: pick up
   `b`, stack it on `a`, then `c`, then `d`, in six steps.
3. Choose **View ▸ The original this was converted from** to see the PDDL
   beside the program.
4. Open [Hanoi](hanoi-p1.pddl) and compare how long its plan is.

## More
- [PDDL and LPS](/docs/user/integrations/pddl): how the files are read and
  paired, how the plans are checked, and the traps.
- [The International Planning Competition](https://www.icaps-conference.org/competitions/),
  where these domains come from.

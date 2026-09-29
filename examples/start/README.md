# Start here — the shortest way in

Six small programs that the tutorial and the start page open. Each shows
one thing that LPS does: it plans, it draws, it reacts to a click, it keeps
running while it waits for the world, or it shows the order in which LPS
does things.

## Start here
- [The wolf, the goat and the cabbage](goat_declarative.pl): the puzzle is
  stated, not solved, and LPS finds the crossings.
- [Blocks](blocks.lps): a tower of seven blocks, rebuilt in the reverse
  order by the planner. [Blocks in 3D](blocks3d.lps) is the same, drawn in 3D.
- [Café](cafe.lps): one coffee machine and three customers. The run shows,
  cycle by cycle, which goal the engine works on first, which action waits,
  and why. [How a program runs](/docs/user/tutorials/how-lps-runs) walks
  through it.
- [Lights](lights.lps): four lamps that you switch on and off by clicking them.
- [Thermostat](thermostat.lps): a program that never ends. It waits for
  events that you send it.

## Try this
1. Open [the wolf, the goat and the cabbage](goat_declarative.pl) and press
   **Run**. The status line says how many cycles the run took.
2. Look at the **Timeline** pane. Each row is a fluent: a fact that holds for
   a stretch of time, such as where the goat is. The events of each cycle, such
   as `row(south,north)`, are listed under the rows.
3. Right-click a bar on the timeline. The explanation says why that fact held
   at that cycle.
4. Open [Blocks in 3D](blocks3d.lps), press **Run**, then choose the **3D**
   pane and press ▶ to watch the tower being rebuilt.
5. Open [Lights](lights.lps). Open the **Live** panel from the top bar and
   start the session, then press **2D** and click the lamps. A rule refuses
   to switch the last lamp off.
6. Open [Thermostat](thermostat.lps), start a live session and send
   `temperature(18)`. The heating comes on.

## More
- [Learning LPS](/docs/user/tutorials/lps-tutorial): the tutorial that
  walks through these programs.
- [Using the editor](/docs/user/guide/ide): the panes, the menus and asking why.

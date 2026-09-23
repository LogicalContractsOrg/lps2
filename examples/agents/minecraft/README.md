# Minecraft — an LPS2 agent in a world it does not control

A bot in a Minecraft world. A small JavaScript program moves the bot, and an
LPS session decides what the bot should do: flee when hurt, hunt when hungry,
craft a tool. The world runs on your own machine, and no Minecraft account
is needed.

## Start here
- [Safety](safety.lps): goals that interrupt whatever the bot is doing when
  its health drops.
- [Hungry](hungry.lps): hunger makes the bot hunt, and a constraint stops it
  from attacking while it is hurt.
- [Crafting](craft.lps): the planner finds the steps from a tree to a
  wooden pickaxe.

## Try this
1. Open [Crafting](craft.lps) and press **Run**. On the **Timeline**, the
   actions come one per cycle: walk to the tree, chop it, make planks, sticks,
   and the pickaxe.
2. Open [Hungry](hungry.lps) and press **Run**. The bot sees a cow and is
   hungry, but it never attacks.
3. Right-click the timeline and ask `why_not(happened(attack(cow)), 4)`. The
   answer names the constraint and the health value that blocked the attack.
4. To watch the bot in a world, follow *Running it without buying Minecraft* in [Details](DETAILS.md):
   `npm install`, then `node demo.mjs --program safety.lps`.

## More
- [Details](DETAILS.md): how the two parts divide the work, how to run the
  world and the viewer, and what to do when the bot prints nothing.
- [Mineflayer](https://github.com/PrismarineJS/mineflayer), the library the bot
  is written with.

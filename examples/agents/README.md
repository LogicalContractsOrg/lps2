# Agents — LPS driving something outside it

Programs in which LPS decides and something outside it acts: a language model
or a game character. The program's rules and constraints stay in charge, and
every action can be asked why it was taken or refused.

## Start here
- [Language model agent](llm/): a language model proposes actions, and an
  approval rule decides whether they run.
- [Minecraft](minecraft/): a bot in a Minecraft world, with LPS choosing what
  it does.

## Try this
1. Open [the approval gate](llm/approval_ide.lps) and read its opening comment:
   it is a six-step walk-through in the live panel.
2. Open [the hungry bot](minecraft/hungry.lps) and press **Run**. The bot is
   hungry and sees a cow, but it is badly hurt.
3. Right-click the timeline and ask `why_not(happened(attack(cow)), 4)`. A
   constraint forbids attacking while health is low, and the answer names it.

## More
- [LPS over MCP](/docs/user/api/mcp): the same engine offered to an agent as a
  set of tools (the Model Context Protocol).

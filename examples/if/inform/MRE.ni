"MRE"

When play begins:
	now the right hand status line is "[time of day]";
	say "The procedure was painless at first: increased strength was the first sign, followed by a sensation of delayed time, as though everyone around you moved more slowly. Your ability to dodge and perform feats of agility doubled, then trebled. You were heralded as a triumph of medicine. They told you there would be no side effects worth speaking of.

They were wrong."

The Base Camp Larder is a room. "This room has been reinforced after each incident -- and there have been dozens in the last two months -- so that it now rivals Fort Knox. Only your new skill and speed enabled you to dodge the motion sensors, knock out the computerized security system, fool the retinal scanner, and punch a hole in the steel containment grating. But you're inside now."


Food is a kind of thing. Food is usually edible. Food has a time period called the satisfaction period. The satisfaction period of a food is usually 5 minutes.

A person can be hungry or replete. The player is hungry.

The Larder contains an apple, a candy bar, and a large plate of pasta. The apple, the candy bar, and the pasta are food. The satisfaction period of the apple is 2 minutes. The satisfaction period of the pasta is 125 minutes.

Check eating something which is not food:
	say "[The noun] might be edible, but it's not what you'd consider really food."

Check eating something when the player is not hungry:
	say "You're not hungry right now."

Carry out eating something:
	now the player is replete;
	hunger resumes in the satisfaction period of the noun from now.


At the time when hunger resumes:
	starvation occurs in three minutes from now;
	now the player is hungry.

At the time when starvation occurs:
	if the player is hungry, end the story saying "You have starved".


Every turn when the player is hungry:
	choose a random row in the Table of Hunger Complaints;
	say "[hunger entry][paragraph break]".

Table of Hunger Complaints
hunger
"Gosh, you're starving."
"It feels as though you haven't eaten in days. Weeks, almost."
"The world seems to slow down and everything becomes sharper and brighter. You are a hunter, a hunter of foodstuffs."
"You find yourself staring at [the random visible thing that is not the player] and wondering how it would taste."

Test me with "eat apple / z / z / z / eat candy bar / z / z / z / z / z / z / z / z / z".

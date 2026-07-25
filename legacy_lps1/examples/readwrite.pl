maxTime(4).
%timeout(3600).
minCycleTime(10). 

fluents  	said(_).
actions 	write(_).
events		read(_). 

initially	said([]).

if	read(X) from T1 to T2  
then 	write(X) from T3 to T4.

write(Word)  initiates	said(NewPhrase)	if said(OldPhrase),  append(OldPhrase, [Word], NewPhrase).
write(_Word) terminates  said(OldPhrase) if said(OldPhrase).

/** <examples>
?- go(Timeline).
?- go. 
*/

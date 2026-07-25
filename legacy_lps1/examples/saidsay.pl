maxTime(4).
%timeout(3600).
minCycleTime(5). 

fluents  	said(_,_).
actions 	say(_,_).

prolog_events listen(_, X). 

%listen(turing, X) :- random(X).
listen(turing, X) :- write('Turing'), read(X).
%listen(turing, X) :- pengine_read(X).  
%listen(turing,X) :- pengines_io:pengine_input, pengines_io:pengine_read(X).
%listen(turing,X) :- get_char(X).   
%listen(turing,X) :- read_term(X, []). 

initially	said(turing, []).%, said(robot, []).

if		listen(turing, X)  	from T1 to T2  
then 	saying(turing, X) 	from T3 to T4.

saying(Agent, X) from T1 to T2		if	say(Agent, X) from T1 to T2.

say(Agent, Word)  initiates	said(Agent, NewPhrase)	if	
							said(Agent, OldPhrase),  
							append(OldPhrase, [Word], NewPhrase).
say(Agent, _Word) terminates  said(Agent, OldPhrase)	if	 
							said(Agent, OldPhrase).

%false	say(Agent, Word1),  say(Agent, Word2),    Word1 \= Word2.

display(said(Person,V), 
	[from:[X,0], to:[RightX,Y], label:(Person:V), type:rectangle,  fontSize:13, fillColor:'#85bb65'/* USD:-)*/ ]
	) :- 
    (Person=turing,X=100, Y=100;Person=robot,X=10, Y=10),
    RightX is X+70.

display(timeless,[ 
    % a display spec can be a list of properties (for one object) or a list of lists (4 objects here:)
    [type:star, center:[250,150], points:9, radius1:20, radius2:25, fillColor:yellow, sendToBack],
    [type:rectangle, from:[0,0], to:[320,200], sendToBack, fillColor:[0,0.746,1]], % R,G,B
    [type:ellipse, shadowOffset:5, shadowColor:darkGray , point:[50,150], size:[110, 40],fillColor: white],
    [type:ellipse,  point:[20,130], size:[90, 30],fillColor: white ]
]).


/** <examples>
?- go(Timeline).
*/

/* lps_plus.pl — LPS2's two translators, and the private lpsPlus repository.

   Two translators of `src/syntax/` are doors to other systems:

     lps_solidity.pl   Misc ▸ Deploy as Solidity, `./lps solidity`
     lps_drools.pl     the DRL front end: File ▸ Open of a `.drl`,
		       `./lps drools`

   From 18 September to November 2026 they lived in the private lpsPlus
   repository; they are back in this one, open like the rest of it. Their
   copyright holder is Miguel Calejo (../../NOTICE), and they are published
   "as is". This module is still the one place that says whether the request
   being served may use them, so callers ask `lps_plus_available/1` first
   and, when it fails, say `lps_plus_message/2`; they call the translators
   module-qualified (`lps_solidity:…`, `lps_drools:…`).

   **Who may use them.** Everybody on the command line and in the gates.
   On a server with no sign-in (a clone of this repository, run on one's
   own machine), every visitor. On a server that has a sign-in (the hosted
   one), every signed-in visitor: the translators are free, and the limits
   on use (../edges/lps_throttle.pl) need somebody to count against. That
   is the capability `converters`, as in Logical English's le_entitlements.

   **The private lpsPlus repository** still holds three things this server
   uses when it finds them: the one sign-in shared with Logical English's
   server (`accounts/lc_accounts.pl`: Google, GitHub, or an account we
   created; `accounts/licenses.csv`: who holds which licence, until when),
   the unlisted examples (`examples/private/`), and the sector pages
   (`docs/sales/pages/`). Where it looks for the checkout, in order:

     $LPS_PLUS_DIR (or $LPSPLUS_DIR)   a checkout, named explicitly — or the
				       word `none`, which means "no lpsPlus,
				       whatever is on this machine" and is how
				       a plain LPS2 is tested here
     ../lpsPlus, ../lpsplus            a checkout beside this one
     /lpsPlus                          the container's mount
     <this repository>/vendor/lpsplus  what tools/vendor_lpsplus.sh put in
				       the image (docs/dev/deploy.md); last, so
				       that a checkout on a development machine
				       always wins over a copy of it (the image
				       names it in LPS_PLUS_DIR anyway)

   A directory counts when it has `accounts/lc_accounts.pl` or
   `examples/private/`. Without lpsPlus every visitor is anonymous and
   everything in this repository works.
*/

:- module(lps_plus, [
	lps_plus_available/1,   % ?Which   (solidity | drools)
	lps_plus_root/1,        % -Dir     the checkout the translators came from
	lps_plus_message/2,     % +Which, -Message
	lps_plus_accounts/0,    % load the sign-in, for a server
	lps_plus_identify/1,    % +Request: who sent it, and what it may use
	lps_plus_visitor/2,     % -Email, -Capabilities
	lps_plus_entitled/1,    % +Capability
	lps_plus_entitlements/1,% -Capabilities (list) or `all`
	lps_plus_set_visitor/2  % +Email, +Capabilities
	]).

:- use_module(library(lists)).

%!	lps_plus_part(?Which, -File, -Module, -Door) is nondet.
%
%	The translators this module loads: what to call it, its file in this
%	directory, the module it defines, and the thing a user of LPS2 would
%	name it by.
lps_plus_part(solidity, 'lps_solidity.pl', lps_solidity,
	      'Deploy as Solidity').
lps_plus_part(drools,   'lps_drools.pl',   lps_drools,
	      'the Drools (DRL) front end').

:- dynamic loaded_part/1.
:- dynamic root/1.

%	This repository's src/, as a search path, for the two modules to reach
%	the core with (`use_module(lps2_src(core/lps_diag))`).
:- prolog_load_context(directory, Syntax),
   file_directory_name(Syntax, Src),
   (   user:file_search_path(lps2_src, Src) -> true
   ;   asserta(user:file_search_path(lps2_src, Src))
   ).

here(Dir) :- prolog_load_context(directory, Syntax), file_directory_name(Syntax, Src),
	file_directory_name(Src, Dir).

named(D) :- member(V, ['LPS_PLUS_DIR', 'LPSPLUS_DIR']), getenv(V, D), D \== '', !.

%	`LPS_PLUS_DIR=none`: a server that is to behave as a checkout with no
%	lpsPlus beside it, wherever it is run.
disabled :- named(D), memberchk(D, [none, '-']).

candidate(D) :- named(D).
candidate(D) :- here(Root), file_directory_name(Root, Parent),
	member(N, ['lpsPlus', lpsplus]), atomic_list_concat([Parent, '/', N], D).
candidate('/lpsPlus').
candidate(D) :- here(Root), atom_concat(Root, '/vendor/lpsplus', D).

checkout(D0, D) :-
	absolute_file_name(D0, D, [file_type(directory), file_errors(fail)]),
	(   atomic_list_concat([D, '/accounts/lc_accounts.pl'], F), exists_file(F)
	;   atomic_list_concat([D, '/examples/private'], P), exists_directory(P)
	), !.

%!	lps_plus_root(-Dir) is semidet.
%
%	The lpsPlus checkout this installation has, if it has one.
lps_plus_root(Dir) :- root(Dir).

%!	lps_plus_available(?Which) is nondet.
%
%	True for each translator that is installed here and that the request
%	being served may use.
lps_plus_available(Which) :- loaded_part(Which), lps_plus_entitled(converters).

%!	lps_plus_message(+Which, -Message) is det.
%
%	What to say instead of doing it: what is missing, and where it comes
%	from. One sentence, because it is shown in a status line as often as
%	on a terminal.
lps_plus_message(Which, Message) :-
	loaded_part(Which), !,
	( lps_plus_part(Which, _, _, Door) -> true ; Door = Which ),
	format(atom(Message),
	       '~w is free, for visitors who have signed in: sign in (top right).',
	       [Door]).
lps_plus_message(Which, Message) :-
	( lps_plus_part(Which, File, _, Door) -> true ; File = '', Door = Which ),
	format(atom(Message),
	       '~w is not installed in this server: its translator \c
		(src/syntax/~w) did not load.',
	       [Door, File]).

%	Load the translators, each guarded: a translator that fails to load
%	takes its own door with it and nothing else.
:- prolog_load_context(directory, Syntax),
   forall(lps_plus_part(Which, File, _, _),
	  (   atomic_list_concat([Syntax, '/', File], F),
	      exists_file(F),
	      catch(use_module(F), E, ( print_message(warning, E), fail ))
	  ->  assertz(loaded_part(Which))
	  ;   true
	  )).

%	The lpsPlus checkout, when there is one.
:- (   disabled
   ->  true
   ;   once(( candidate(C), checkout(C, Root) ))
   ->  assertz(root(Root))
   ;   true
   ).

/* ------------------------------------------------------------------------
   Signing in, and what the request being served may use
   ------------------------------------------------------------------------ */

:- dynamic accounts_loaded/0.

%!	lps_plus_accounts is det.
%
%	Loads lpsPlus's sign-in (accounts/lc_accounts.pl) when this
%	installation has it, and makes this process a server: from now on a
%	thread that no request has identified may use nothing licensed. Called
%	by lps_http:lps_server/2. Without lpsPlus every visitor is anonymous,
%	and may use the translators (lps_plus_identify/1).
lps_plus_accounts :-
	retractall(default_caps(_)), assertz(default_caps(none)),
	(   accounts_loaded
	->  true
	;   \+ disabled,
	    once(( candidate(C),
		   absolute_file_name(C, D, [file_type(directory), file_errors(fail)]),
		   atomic_list_concat([D, '/accounts/lc_accounts.pl'], F),
		   exists_file(F) ))
	->  use_module(F),
	    assertz(accounts_loaded)
	;   true
	).

:- thread_local request_visitor/2.	% Email, Capabilities
:- dynamic default_caps/1.
default_caps(all).

%!	lps_plus_identify(+Request) is det.
%
%	Who sent Request (lpsPlus's sign-in cookie, the one Logical English's
%	server sets too), remembered for the rest of the request. Called for
%	every request, so a pooled worker thread never carries one visitor's
%	licence into the next visitor's request.
lps_plus_identify(Request) :-
	retractall(request_visitor(_, _)),
	(   accounts_loaded,
	    catch(lc_accounts:lc_request_user(Request, User), E,
		  ( print_message(warning, E), fail ))
	->  get_dict(email, User, Email),
	    get_dict(capabilities, User, Caps0),
	    %  the translators are free for whoever signed in
	    ( memberchk(converters, Caps0) -> Caps = Caps0 ; Caps = [converters|Caps0] ),
	    assertz(request_visitor(Email, Caps))
	;   accounts_loaded
	->  assertz(request_visitor(anonymous, []))
	;   %  a server with no sign-in: nobody can sign in, so nobody has to
	    assertz(request_visitor(anonymous, [converters]))
	).

%!	lps_plus_set_visitor(+Email, +Capabilities) is det.
%
%	The request's visitor, when a key says who it is rather than the
%	sign-in cookie: a call to /mcp with a key (lps_throttle.pl). It
%	replaces what lps_plus_identify/1 found for this request.
lps_plus_set_visitor(Email, Caps0) :-
	retractall(request_visitor(_, _)),
	%  a key names an account, and the translators are free for any account
	(   Email \== anonymous, \+ memberchk(converters, Caps0)
	->  Caps = [converters|Caps0]
	;   Caps = Caps0
	),
	assertz(request_visitor(Email, Caps)).

%!	lps_plus_visitor(-Email, -Capabilities) is semidet.
%
%	The signed-in visitor of the request being served; fails for an
%	anonymous one.
lps_plus_visitor(Email, Caps) :-
	request_visitor(Email, Caps),
	Email \== anonymous.

%!	lps_plus_entitlements(-Caps) is det.
%
%	What the request being served may use: a list of capabilities, or
%	`all` (the command line, the gates, `NO_RESTRICTIONS=true`).
lps_plus_entitlements(Caps) :-
	(   getenv('NO_RESTRICTIONS', true)
	->  Caps = all
	;   request_visitor(_, C)
	->  Caps = C
	;   default_caps(all)
	->  Caps = all
	;   Caps = []
	).

%!	lps_plus_entitled(+Capability) is semidet.
lps_plus_entitled(Cap) :-
	lps_plus_entitlements(Caps),
	(   Caps == all -> true ; memberchk(Cap, Caps) ).

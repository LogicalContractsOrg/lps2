/* lps_plus.pl — the two translators that are not in this repository.

   Two of `src/syntax/`'s translators are **not here**: they live in the
   private lpsPlus repository, beside the eleven readers and writers of other
   systems that were always there (`lpsPlus/migration/`).

     lps_solidity.pl   Misc ▸ Deploy as Solidity, `./lps solidity`
		       → lpsPlus/migration/solidity/lps_solidity.pl
     lps_drools.pl     the DRL front end: File ▸ Open of a `.drl`,
		       `./lps drools`
		       → lpsPlus/migration/drools/lps_drools.pl

   Why: `docs/sales/MarketingPlan.md` §2.2 in that repository, the section on
   publishing LPS2. Of everything the engine holds, the Solidity writer is the
   one piece that sits in a market with money in it, and the DRL reader is the
   one a BRMS vendor could take; both were moved out (18 September 2026) so
   that the licence decision about LPS2 is not also a decision about them.

   **They are optional, in the same sense LE2 is** (`src/edges/lps_le.pl`):
   nothing else in LPS2 references them, and without them the engine, the IDE,
   the CLI and every gate work exactly as they do — the only things that stop
   working are the two doors above, each of which then says what is missing
   rather than failing obscurely. That is why this module loads them with a
   guard rather than with a `use_module` directive: a directive would make a
   missing lpsPlus a *load* error for a file on the CLI's path.

   Where it looks for the checkout, in order:

     $LPS_PLUS_DIR (or $LPSPLUS_DIR)   a checkout, named explicitly — or the
				       word `none`, which means "load neither,
				       whatever is on this machine" and is how
				       a plain LPS2 is tested here
     ../lpsPlus, ../lpsplus            a checkout beside this one
     /lpsPlus                          the container's mount
     <this repository>/vendor/lpsplus  what tools/vendor_lpsplus.sh put in
				       the image (docs/dev/deploy.md); last, so
				       that a checkout on a development machine
				       always wins over a copy of it (the image
				       names it in LPS_PLUS_DIR anyway)

   A directory counts when one of the two files is under it. Callers ask
   `lps_plus_available/1` first and, when it fails, say `lps_plus_message/2`;
   they call the translators module-qualified (`lps_solidity:…`,
   `lps_drools:…`) so that this file is the only place that knows they can be
   absent.

   The two modules are written for LPS2 and use its core, which they reach
   through the `lps2_src` search path declared below — so they do not care
   which directory they are read from.

   **Signing in, and the licences.** lpsPlus also holds the one sign-in that
   this server shares with Logical English's (`accounts/lc_accounts.pl`:
   Google, GitHub, or an account we created; `accounts/licenses.csv`: who
   holds which licence, until when). A server loads it (lps_plus_accounts/0)
   and asks, for every request, who sent it (lps_plus_identify/1, from an HTTP
   request expansion in lps_http.pl). The two translators above, and the
   translators of other systems that the Logical English in this process
   offers, belong to the licence "with extensions" — the capability
   `converters` — so on a server lps_plus_available/1 is true only for a
   visitor who holds it. On the command line, and in the gates, which no
   request limits, everything installed is available, as before.
*/

:- module(lps_plus, [
	lps_plus_available/1,   % ?Which   (solidity | drools)
	lps_plus_root/1,        % -Dir     the checkout the translators came from
	lps_plus_message/2,     % +Which, -Message
	lps_plus_accounts/0,    % load the sign-in, for a server
	lps_plus_identify/1,    % +Request: who sent it, and what it may use
	lps_plus_visitor/2,     % -Email, -Capabilities
	lps_plus_entitled/1,    % +Capability
	lps_plus_entitlements/1 % -Capabilities (list) or `all`
	]).

:- use_module(library(lists)).

%!	lps_plus_part(?Which, -RelativePath, -Module, -Door) is nondet.
%
%	The translators this module may load: what to call it, where it is in
%	an lpsPlus checkout, the module it defines, and the thing a user of
%	LPS2 would name it by.
lps_plus_part(solidity, 'migration/solidity/lps_solidity.pl', lps_solidity,
	      'Deploy as Solidity').
lps_plus_part(drools,   'migration/drools/lps_drools.pl',     lps_drools,
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
	lps_plus_part(_, Rel, _, _),
	atomic_list_concat([D, '/', Rel], F),
	exists_file(F), !.

%!	lps_plus_root(-Dir) is semidet.
%
%	The lpsPlus checkout the translators were loaded from.
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
	(   lps_plus_visitor(_, _)
	->  format(atom(Message),
		   '~w needs the licence "with extensions", which this account \c
		    does not hold.', [Door])
	;   format(atom(Message),
		   '~w needs the licence "with extensions": sign in (top right) \c
		    with an account that holds it.', [Door])
	).
lps_plus_message(Which, Message) :-
	( lps_plus_part(Which, Rel, _, Door) -> true ; Rel = '', Door = Which ),
	file_base_name(Rel, File),
	format(atom(Message),
	       '~w is not installed in this server: its translator (~w) lives in \c
		the private lpsPlus repository. Point LPS_PLUS_DIR at a checkout, \c
		or put one beside this one (../lpsPlus).',
	       [Door, File]).

%	Load whichever are installed. `use_module/1` rather than a directive
%	per file: the path is only known now.
:- (   disabled
   ->  true
   ;   once(( candidate(C), checkout(C, Root) ))
   ->  assertz(root(Root)),
       forall(( lps_plus_part(Which, Rel, _, _),
		atomic_list_concat([Root, '/', Rel], F),
		exists_file(F) ),
	      ( use_module(F), assertz(loaded_part(Which)) ))
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
%	by lps_http:lps_server/2. Without lpsPlus every visitor is anonymous.
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
	    get_dict(capabilities, User, Caps),
	    assertz(request_visitor(Email, Caps))
	;   assertz(request_visitor(anonymous, []))
	).

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

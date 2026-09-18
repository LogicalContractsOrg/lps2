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
*/

:- module(lps_plus, [
	lps_plus_available/1,   % ?Which   (solidity | drools)
	lps_plus_root/1,        % -Dir     the checkout the translators came from
	lps_plus_message/2      % +Which, -Message
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
%	True for each translator that is installed here.
lps_plus_available(Which) :- loaded_part(Which).

%!	lps_plus_message(+Which, -Message) is det.
%
%	What to say instead of doing it: what is missing, and where it comes
%	from. One sentence, because it is shown in a status line as often as
%	on a terminal.
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

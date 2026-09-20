/* pack.pl — what goes into a WebAssembly build.
 *
 * The browser build carries its own file system: LPS2's Prolog, the examples
 * and the pieces of the legacy corpus the IDE offers, unpacked into the
 * worker's virtual file system before the first request. This file decides
 * what that is.
 *
 * Three rules, and the reasons for them:
 *
 *   * **the extension list is short.** `examples/` is nearly a gigabyte, all
 *     but a few megabytes of it the Minecraft agent's `node_modules` and its
 *     texture packs. What the IDE offers is programs and the READMEs it takes
 *     folder labels from, so that is what ships.
 *   * **the same directories the IDE skips.** `node_modules`, `sources`,
 *     `expected`, `phase0`, `logs`, `world` — the list is
 *     lps_api:own_example_subdir/3's, because a folder the example tree does
 *     not show is a folder nothing can open.
 *   * **`vendor/` only when asked.** `vendor/le2` is a copy of *another*
 *     repository, made by tools/vendor_le2.sh from whatever checkout was to
 *     hand — which may be one with the private grammar extensions in it.
 *     `--with-le` includes it; build.sh refuses to do so publicly when it
 *     finds one of those files there.
 *
 * `payload_files(-Files)` is the list, relative to the repository root.
 * build.sh asks for it and hands it to the packer; nothing else decides what
 * ships.
 */

:- module(lps_wasm_pack, [
	payload_files/1,         % -Files:list(atom)
	payload_files/2,         % +Options, -Files
	print_payload_files/0,
	print_payload_files/1    % +Options
	]).

:- use_module(library(lists)).

%!	payload_tree(?Spec) is nondet.
%
%	dir(Rel, Extensions) — every file under Rel with one of those
%	extensions, recursively.
payload_tree(dir(src,                     [pl])).
payload_tree(dir(wasm,                    [pl])).
payload_tree(dir(examples,                [le, lps, pl, pddl, ni, drl, md, txt])).
payload_tree(dir('legacy_lps1/examples',  [pl, lpsw])).
%	Ten corpus programs `:- include(system(...))` their way into these.
payload_tree(dir('legacy_lps1/engine/system', [pl])).
%	The user documentation, as text. Not for reading — the site serves the
%	same files for that — but because the assistant searches it for the
%	request and cites what it finds (lps_docs_search.pl, over docs/user and
%	its nav.json).
payload_tree(dir('docs/user', [md, json])).

%!	never(+Rel) is semidet.
never('src/edges/lps_http.pl').   % the HTTP server: it cannot load here, by design
never('src/lps.pl').              % which loads it
never(Rel) :- sub_atom(Rel, _, _, _, '/.').
never(Rel) :- sub_atom(Rel, 0, 1, _, '.').

%	The directories the IDE's own example tree skips.
skip_dir(node_modules).
skip_dir(sources).
skip_dir(expected).
skip_dir(phase0).
skip_dir(logs).
skip_dir(world).
skip_dir(dist).

payload_files(Files) :- payload_files([], Files).

%!	payload_files(+Options, -Files) is det.
%
%	Options: `le(true)` to include the vendored Logical English at
%	vendor/le2, which makes the build one that compiles `.le` in the page.
payload_files(Options, Files) :-
	repo_root(Root),
	findall(Rel,
		( ( payload_tree(Spec)
		  ; memberchk(le(true), Options),
		    Spec = dir('vendor/le2', [pl, csv])
		  ),
		  Spec = dir(Sub, Exts),
		  tree_file(Root, Sub, Exts, Rel),
		  \+ never(Rel) ),
		Files0),
	sort(Files0, Files).

repo_root(Root) :-
	module_property(lps_wasm_pack, file(F)),
	file_directory_name(F, Dir),
	file_directory_name(Dir, Root).

tree_file(Root, Sub, Exts, Rel) :-
	atomic_list_concat([Root, '/', Sub], Dir),
	exists_directory(Dir),
	directory_files(Dir, Entries),
	member(Entry, Entries),
	Entry \== '.', Entry \== '..',
	\+ sub_atom(Entry, 0, 1, _, '.'),
	atomic_list_concat([Dir, '/', Entry], Path),
	atomic_list_concat([Sub, '/', Entry], Rel0),
	(   exists_directory(Path)
	->  \+ skip_dir(Entry),
	    \+ read_link(Path, _, _),          % never out through a link
	    tree_file(Root, Rel0, Exts, Rel)
	;   file_name_extension(_, Ext, Entry),
	    memberchk(Ext, Exts),
	    Rel = Rel0
	).

print_payload_files :- print_payload_files([]).
print_payload_files(Options) :-
	payload_files(Options, Files),
	forall(member(F, Files), writeln(F)).

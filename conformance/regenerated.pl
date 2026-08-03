/* regenerated.pl — goldens that LPS(2) owns.

   §I.1.5 allows a corpus entry to be adjudicated and its `.lpst` regenerated,
   provided the reason is written down and reviewed. This file is that record.
   Each entry names the slug, the replacement golden under conformance/goldens/,
   and why the 2021 trace cannot stand.

   The regenerated goldens live *here*, never in legacy_lps1/ — that tree is
   read-only, and keeping the original alongside is what makes the two
   comparable.

   The overriding golden is used only when the engine under test is LPS(2).
   Running the legacy engine still compares it against its own 2021 trace,
   which is the honest thing to do: these are exactly the tests the legacy
   engine cannot reproduce deterministically.
*/

:- module(regenerated, [ regenerated_golden/3 ]).

:- use_module(library(filesex)).
:- use_module(corpus).

%!	regenerated_golden(?Slug, -File, -Reason) is nondet.
regenerated_golden(Slug, File, Reason) :-
	regenerated(Slug, Reason),
	lps2_root(Root),
	atomic_list_concat([Root, '/conformance/goldens/', Slug, '.lpst'], File),
	exists_file(File).

/* **Empty, and that is the result.**

   The expectation going in — the user having asked for regeneration — was that
   the eleven wall-clock-bound programs would lose their goldens: their cycle
   count depends on machine speed, so under §I.2.3's deterministic clock they
   could hardly be expected to agree with a trace recorded on 2021 hardware.

   They agree anyway. Every one of them turns out to declare
   `simulatedRealTimePerCycle/1` as well as `maxRealTime/1`, so its clock was
   already simulated and already deterministic; what `maxRealTime` bounded was
   simulated seconds, not elapsed ones. Replacing `get_time/1` with a function
   of cycle time changed nothing they could observe.

   The two entries that do fail — `forTesting/realTimeObservations.pl` and
   `CLOUT_workshop/life.pl` — fail *identically in both engines*, so their
   goldens are stale rather than unreproducible, and they are recorded in
   conformance/adjudicated.pl instead. Regenerating them would have replaced a
   provably wrong golden with an unreviewed one and hidden the fact that the
   two engines agree.

   The mechanism stays because §I.1.5 needs somewhere for a regenerated golden
   to live, and because the next corpus addition may need one.
*/
regenerated(_Slug, _Reason) :- fail.

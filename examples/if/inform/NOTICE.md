# Inform sources, for the assertion front end

Eleven Inform 7 programs, copied from the Inform repository
(https://github.com/ganelson/inform, copyright Graham Nelson 2006–2022,
Artistic License 2.0): eight of `inform7/Tests/Test Cases/` and three worked
examples of *Writing with Inform* and *The Recipe Book*
(`resources/Documentation/Examples/`), with their explanatory prose removed.
They are the corpus of `tools/inform_test.pl`, which translates their
assertions into stories on `examples/if/world.le` and checks the result
against the initial state read by hand from each program, and — where the
story has no rules of its own — against the transcript-derived expectations
of the hand-written stories in `examples/if/`.

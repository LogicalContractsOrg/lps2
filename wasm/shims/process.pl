/** <module> library(process), for a machine with no processes

    A browser tab cannot start a program. One module imports this library:
    lps_le.pl, which can run an LE2 checkout as a *subprocess* (LPS_LE2_DIR,
    the isolated transport of docs/dev/le-lps-interface.md). In the browser the
    other transport is the one that works — the in-process library, vendored
    into the payload — and this one refuses.

    The refusal is an existence error on the executable, which is what
    lps_le.pl already handles: a machine with no SWI-Prolog to start is a case
    the server build has always had to answer for.
*/

:- module(process, [
    process_create/3,           % +Exe, +Args, +Options
    process_wait/2,             % +PID, -Status
    process_wait/3,             % +PID, +Status, +Options
    process_kill/1,             % +PID
    process_kill/2,             % +PID, +Signal
    process_id/1                % -PID
    ]).

process_create(Exe, _Args, _Options) :-
    throw(error(existence_error(source_sink, Exe),
                context(process:process_create/3,
                        'a WebAssembly build cannot start a program'))).

process_wait(_PID, exit(1)).
process_wait(_PID, exit(1), _Options).
process_kill(_PID).
process_kill(_PID, _Signal).
process_id(0).

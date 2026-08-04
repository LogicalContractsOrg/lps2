# vendor/

Copies of other repositories, for the image. Nothing here is edited by hand and
nothing here is committed.

`le2/` is a minimal Logical English — LE2's language service and its keyword
tables, not its editor or its web API — put there by `tools/vendor_le2.sh` so
that a deployed LPS2 can compile `.le` programs in its own process
(`docs/le_lps_interface.md` §3.5). Re-run the script to refresh it; edit the
LE2 checkout, never this copy.

An LPS2 image built without it works exactly as before: Logical English is
absent, and says so.

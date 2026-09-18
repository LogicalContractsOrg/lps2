# vendor/

Copies of other repositories, for the image. Nothing here is edited by hand and
nothing here is committed.

`le2/` is a minimal Logical English — LE2's language service and its keyword
tables, not its editor or its web API — put there by `tools/vendor_le2.sh` so
that a deployed LPS2 can compile `.le` programs in its own process
(`docs/dev/le-lps-interface.md` §3.5). Re-run the script to refresh it; edit the
LE2 checkout, never this copy.

An LPS2 image built without it works exactly as before: Logical English is
absent, and says so.

`lpsplus/` is the pair of translators that are LPS2's but live in the private
lpsPlus repository — `lps_solidity.pl` (Misc ▸ Deploy as Solidity) and
`lps_drools.pl` (the DRL front end) — put there by
`tools/vendor_lpsplus.sh` in the layout they have in that checkout
(`src/syntax/lps_plus.pl` says why they are not here). An image built without
it is a public LPS2: those two doors say what is missing, and everything else
is unchanged.

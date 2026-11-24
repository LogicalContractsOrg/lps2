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

`lpsplus/` is what a server uses of the private lpsPlus repository: the
sign-in it shares with Logical English's server and the licences (`accounts/`),
the unlisted examples (`examples/private/`), and the sector pages
(`docs/sales/pages/`, for example `/insurance`). `tools/vendor_lpsplus.sh` puts
them there in the layout they have in that checkout. No translator is in
`lpsplus/`: `lps_solidity.pl` (Misc ▸ Deploy as Solidity) and `lps_drools.pl`
(the DRL front end) lived in lpsPlus from 18 September to November 2026, and
are back in `src/syntax/`, open source. An image built without `lpsplus/` is a
public LPS2: it has no sign-in, no unlisted examples and no sector pages, and
everything else is unchanged, the two translators included.

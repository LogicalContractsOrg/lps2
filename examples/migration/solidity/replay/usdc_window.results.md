# Replay: 0xa0b86991c6218b36c1d19d4a2e9eb0ce3606eb48 against its LE twin

Ethereum mainnet blocks 25968821–25968823 (state before: block 25968820), fetched 2026-09-13T13:31:10.288Z from https://ethereum-rpc.publicnode.com.

Implementation behind the proxy: 0x43506849d7c04f9138d1a2050bbf3a0c054402dd (Sourcify full match: FiatTokenV2_2).

| | |
|---|---|
| logs replayed | 201 (197 transfers, 3 mints, 1 burns) |
| values compared | 215 (the total supply and the balance of every account the logs touch) |
| **agree with the chain** | **215 of 215** |
| LPS2 run | 2.34 s |

Every balance and the total supply the twin reaches are the chain's.

Approximated: a Transfer made by `transferFrom` is replayed as a `transfer` by the owner of the funds (the same balances; the allowance spent is not in the logs). Approval logs are not replayed.

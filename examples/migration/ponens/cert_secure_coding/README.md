# CERT C/C++ Secure Coding

The SEI CERT secure-coding risk model — Severity × Likelihood × Remediation → Priority → Level L1/L2/L3 — and its prioritized-remediation process, as computable policies. Covers CERT C and CERT C++.

The 11 policies of the Ponens pack `cert-secure-coding`, as a program of Logical English for LPS: each policy is a law that records a breach, and each of the 2 traces under `sources/traces/` is a scenario. Choose a scenario and press **Run**: the breaches are on the timeline, at the step where each policy failed, and the comment above each scenario says what Ponens's own evaluator found on the same trace.

Ledger: 11 policies encoded, 0 kept as residue (formulas Ponens's own parser cannot read).

The pack is Imandra's reading of: SEI CERT C and CERT C++ Secure Coding Standards (Carnegie Mellon SEI).

Written by lpsPlus's Ponens translator from github.com/imandra-ai/ponens (commit 2f91978 2026-10-13, MIT licence, Imandra Inc.; `sources/LICENSE`).

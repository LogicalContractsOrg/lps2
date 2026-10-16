# Ponens policies in Logical English for LPS

Ponens (github.com/imandra-ai/ponens, Imandra Inc., MIT licence) checks the record of an AI agent's session, a *trace*, against *policies* written in a temporal logic. Each folder here is one of its policy packs as a program of Logical English for LPS. Each policy is a causal law that records a breach at the step where the policy fails, and each trace is a scenario. The comment above each scenario says what Ponens's own evaluator found on the same trace.

| Pack | Policies | Traces | Encoded | Residue |
|---|---|---|---|---|
| [Agentic AI Runtime Governance](agentic_ai_runtime_governance/) | 21 | 14 | 21 | 0 |
| [Apply Formal Methods Where It Makes Sense](apply_formal_methods/) | 8 | 8 | 8 | 0 |
| [CERT C/C++ Secure Coding](cert_secure_coding/) | 11 | 2 | 11 | 0 |
| [CMS AI Guidance (TRA)](cms_ai_guidance/) | 13 | 2 | 13 | 0 |
| [DO-178C Software Assurance](do_178c_software_assurance/) | 19 | 2 | 19 | 0 |
| [MiFID II AI in Investment Services](esma_mifid_ai_investment_services/) | 14 | 2 | 14 | 0 |
| [Supervisory Recordkeeping & Disclosure](iosco_supervisory_recordkeeping/) | 11 | 2 | 11 | 0 |
| [FIX Certification with IPL](ipl_fix_certification/) | 12 | 8 | 12 | 0 |
| [JSF Air Vehicle C++](jsf_av_cpp/) | 12 | 2 | 12 | 0 |
| [MISRA C](misra_c/) | 12 | 2 | 12 | 0 |
| [MISRA C++](misra_cpp/) | 12 | 2 | 12 | 0 |
| [NIST AI Risk Management Framework](nist_ai_rmf/) | 15 | 2 | 15 | 0 |
| [NIST SSDF (Secure Software Development)](nist_ssdf/) | 14 | 2 | 14 | 0 |
| [Ponens's own policies](ponens_defaults/) | 39 | 8 | 38 | 1 |

How the translation works, and how it was checked: the integration guide, [Ponens policies](/docs/user/integrations/ponens).

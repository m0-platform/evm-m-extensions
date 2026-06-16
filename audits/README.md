# Prior Audit Reports — coverage on this branch

The seven reports in this directory audited `main`'s **unshielded** code, compiled with
**stock solc 0.8.26** (last common ancestor: merge-base `87a2f42`). **None of them cover
the Seismic branch**: not the shielded `MYieldToOne` rewrite (`suint256`
balances/allowances, gated reads, infra allowlist, encrypted events), nor any bytecode
produced by the ssolc compiler fork — including the "unchanged" contracts
(SwapFacility, the other extensions), whose source is identical modulo pragma but whose
deployed bytecode on Seismic is a fresh, unaudited ssolc/mercury compilation. Scope for
the Seismic audit is summarized in the [repo README](../README.md#audit-scope).

| Report                                                              | Auditor               | Covers                                             |
| ------------------------------------------------------------------- | --------------------- | -------------------------------------------------- |
| `Certora MExtension Security Assessment Final Report.pdf`           | Certora               | `main` M Extensions (unshielded, stock solc)       |
| `ChainSecurity_M0_M_Extensions_audit.pdf`                           | ChainSecurity         | `main` M Extensions (unshielded, stock solc)       |
| `ChainSecurity_M0_M_Extensions_audit_draft.pdf`                     | ChainSecurity (draft) | `main` M Extensions (unshielded, stock solc)       |
| `Guardian Audits M0 Extensions Report Aug 5.pdf`                    | Guardian Audits       | `main` M Extensions (unshielded, stock solc)       |
| `GuardianAudits_M0_MExtensions_report.pdf`                          | Guardian Audits       | `main` M Extensions (unshielded, stock solc)       |
| `JMI/2025_12_10_Final_M0_Collaborative_Audit_Report_1765332345.pdf` | Collaborative (JMI)   | `main` JMIExtension (unshielded, stock solc)       |
| `JMI/M0_EVM-M_Extensions_Review_report.pdf`                         | JMI review            | `main` M Extensions / JMI (unshielded, stock solc) |

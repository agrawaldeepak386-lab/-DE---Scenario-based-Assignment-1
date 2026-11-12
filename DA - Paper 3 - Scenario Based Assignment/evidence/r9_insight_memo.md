# Insight memo — HOS-017 vs HOS-022 (rejection rates)

Source: `claims.analytics.r9_paradox` (built from the trusted star schema; decided = approved + rejected + settled; rejection rate = rejected ÷ decided).

## Question

Two hospitals — **HOS-017** (Coimbatore Care Hospital 17) and **HOS-022** (Pune Care Hospital 22) — need their rejection rates compared. Rejection rate is **rejected ÷ decided** claims (decided = approved + rejected + settled; a claim still at `submitted` is on neither side of the fraction).

## Overall

| Hospital | Decided | Rejected | Rejection rate |
| --- | --- | --- | --- |
| HOS-017 | 100 | 21 | **0.21** |
| HOS-022 | 100 | 11 | **0.11** |

On the headline number, **HOS-017 looks almost twice as bad as HOS-022** (21% vs 11%).

## Split by claim type

| Claim type | HOS-017 decided → rejected (rate) | HOS-022 decided → rejected (rate) | Who is worse |
| --- | --- | --- | --- |
| cashless | 20 → 1 (**0.05**) | 80 → 5 (**0.0625**) | HOS-022 |
| reimbursement | 80 → 20 (**0.25**) | 20 → 6 (**0.30**) | HOS-022 |

Within **both** claim types, **HOS-022 is actually the worse hospital** — the headline number had it backwards.

## Why the overall number misleads

The reversal is driven by the hospitals' **claim-type mix**, not by their rejection behaviour: HOS-017's decided claims are 80% reimbursement (the high-rejection type, ~26% average rejection) while HOS-022's are 80% cashless (the low-rejection type, ~6% average rejection). Aggregating over an uneven mix makes the hospital with the *safer* mix look safer regardless of how it handles each claim type. The statistical effect behind this reversal — an association that reverses direction when data is aggregated over a confounding subgroup variable — is its standard textbook name: **Simpson's paradox** (the confounder here is claim type).

## Recommendation

Never compare the two hospitals on the aggregate number alone. Compare **like with like — within claim type** (where HOS-022 is worse on both), or use a mix-adjusted (standardised) rate if a single number is required. The compliance review should treat `claims.analytics.r9_paradox` (overall row `ALL` + per-claim-type rows) as the reporting basis.

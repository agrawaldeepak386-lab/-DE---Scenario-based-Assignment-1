# R6 Prompting note — Saffron Shield Claims Q&A

Space: **Saffron Shield Claims Q&A** (`01f1ddcedbb9106b99b8b67b07bd1570`), scoped to `claims.analytics` only (`fact_claims`, `dim_date`, `dim_member`, `dim_hospital`, `dim_plan`, `w01`).

This note records every prompting decision made while tuning the space, and names the benchmark ID(s) from `genie_benchmarks.json` that each fix addressed. Benchmark run results are in [benchmark_run.json](benchmark_run.json); final score **10/10 correct** (pass gate: at least 8 of 10).

## Fixes and the benchmark IDs they addressed

### Fix 1 — Rejection rate is over DECIDED claims, never all claims
- **What was done:** Space instruction: rejection rate ALWAYS means rejected / decided, where decided = approved + rejected + settled. Claims still at `submitted` sit on neither side of the fraction. Never divide by all claims.
- **Why:** The naive reading (rejected / all rows) understates the rate (397/3,046 = 0.1303 vs the correct 397/2,699 = 0.1471) because 347 submitted claims are still undecided.
- **Benchmark IDs addressed:** **B02** (overall rejection rate), **B03** (per-plan rejection rates).

### Fix 2 — NULLIF guard on the decided denominator (divide-by-zero hardening)
- **What was done:** Trusted example 2 originally computed the rate with a bare `/` on the decided denominator; it was rewritten with `NULLIF(..., 0)` so a group with zero decided claims returns NULL instead of erroring or producing a misleading value.
- **Benchmark IDs addressed:** **B02**, **B03** (any slice where a subgroup could have an empty decided set).

### Fix 3 — Paid = approved amount of SETTLED claims only
- **What was done:** Space instruction: "paid" always means the approved amount of claims whose status is `settled` — not approved claims, not all claims.
- **Benchmark IDs addressed:** **B05** (total paid on settled GOLD_IND claims = 42,460,425.14).

### Fix 4 — Plan = the plan version at admission (point-in-time, not current)
- **What was done:** Space instruction: whenever a question mentions a member's or claim's plan, use `fact_claims.plan_sk` (the plan in force at admission), never the member's current plan.
- **Benchmark IDs addressed:** **B03** (per-plan rejection rate), **B05** (paid for GOLD_IND).

### Fix 5 — Loss ratio far above 1 is expected; do not "fix" it
- **What was done:** Space instruction telling Genie that loss ratios in this synthetic data reach double digits (w01: paid / earned premium) and must not be re-scaled, capped, or second-guessed.
- **Benchmark IDs addressed:** **B09** (highest-loss-ratio plan — CORP_GROUP at 38.58 without the model "correcting" the number).

### Fix 6 — Weekly = Monday-starting week of submission date
- **What was done:** Space instruction pinning the week definition so date-bucket questions bucket identically every time.
- **Benchmark IDs addressed:** none of B01–B10 directly (held out for the weekly-rejection dashboard/alert in R7); included so month/bucket questions (**B01**) stay anchored to `dim_date` rather than free-form date math.

## Coverage rule check
The space's trusted examples cover four canonical question shapes (status counts; hospital rejections with decided-only rate; monthly trend; rejection-code breakdown). The 10 benchmark questions reuse those shapes with different entities, months, and wordings — none is a reworded copy of a trusted example, so the benchmark is held out.

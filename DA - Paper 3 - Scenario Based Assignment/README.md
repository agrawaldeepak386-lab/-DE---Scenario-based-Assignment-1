# DA — Paper 3 Scenario Based Assignment

Saffron Shield claims analytics, R1–R9. All deliverable tables and views live in the `claims.analytics` schema; data frozen as of 2026-06-30.

## R1 — Star schema

Notebook: `R1_Star_Schema`.

- `claims.analytics.dim_date` (365 daily rows), `dim_member` (500 members, no PII), `dim_hospital` (40 hospitals), `dim_plan` (651 SCD2 plan versions) and `fact_claims` (3,046 rows).
- `fact_claims` joins each claim to the plan version in force at admission (point-in-time join, verified exactly-once), is clustered on `admission_date_key`, and carries all 5 primary-key and 6 foreign-key constraints named per the delivery contract.

## R2 — SQL Editor analytics (saved queries)

Saved queries `q01`–`q06`. Screenshots: `evidence/screenshots/r2_saved_queries_Q01.png` … `Q06.png`.

- q01 claim-status counts: 452 approved / 397 rejected / 1,850 settled / 347 submitted (= 3,046 total; overall rejection rate 0.1471 = 397 ÷ 2,699 decided).
- q02 highest-paid hospitals: HOS-022 Rs 6,922,038.95 (85 settled claims), HOS-017 Rs 5,507,639.27, HOS-011 Rs 5,263,127.47.
- q03 monthly claim volume and billed amount, Jul 2025 → Jun 2026 (peak 288 claims in Mar 2026; billed peak Rs 28,991,742.84 in Apr 2026).
- q04 average turnaround ~15.1–15.9 days across the cashless/reimbursement × in/out-of-network segments.
- q05 rejection reasons nearly flat: RJ-DOCS 26.7%, RJ-EXCLUSION 24.9%, RJ-WAITING 24.7%, RJ-NON-DISCLOSURE 23.7%.
- q06 share of claims with room rent over the cap, by plan: SILVER_IND 0.5672, SENIOR 0.4689, CORP_GROUP 0.1571, GOLD_IND 0.1363.

## R3 — Window functions & cohorts

Notebook: `R3_Window_Functions_Cohorts` (w01–w04, all materialized in `claims.analytics`).

- `w01` — monthly loss ratio per plan: paid (approved amount of settled claims, by settled month and plan at admission) ÷ earned premium (1/12 of the annual premium for every plan version active any day of the month, no proration).
- `w02` — rolling 3-month loss ratio as a single ratio over the current month + two prior months (sum paid ÷ sum earned over the window, not an average of monthly ratios).
- `w03` — hospital ranking by total paid within each city tier, using `RANK()` so genuinely tied hospitals share a rank.
- `w04` — member cohorts by policy-start quarter (2023-Q1 … 2025-Q4), with members, claimants, claim counts, claims per claimant and cumulative members.

## R4 — Metric views

Notebook: `R4_Metric_Views`.

- Unity Catalog metric views `claims.analytics.mv_claims` and `mv_loss_ratio` (MEASURE-based KPIs; fallback `metric_definitions` + `v_metrics_by_plan` also built).
- Verified `mv_claims` rejection_rate per plan equals the direct-SQL recomputation: CORP_GROUP 0.1243, GOLD_IND 0.1565, SENIOR 0.1603, SILVER_IND 0.1345.

## R5 — Dashboard

Prep notebook: `R5_Dashboard_Prep`; dashboard: `Claims Ops.lvdash.json`.

- KPI counters: 3,046 claims, Rs 177,758,760.28 approved, 0.1471 rejection rate, 15.7-day average turnaround.
- Monthly claim trend, paid-by-hospital bar chart and rejection-code breakdown, with plan_code, city_tier and date filters. Screenshot: `evidence/screenshots/r5_claims_ops.png`.

## R6 — Genie space

Genie space "Saffron Shield Claims Q&A" (id 01f1ddcedbb9106b99b8b67b07bd1570) over `fact_claims`, `dim_date`, `dim_member`, `dim_hospital`, `dim_plan` and `w01`.

- Domain-vocabulary instructions, 4 trusted examples (fixed example 2 uses NULLIF on the decided denominator) and the benchmark procedure from `genie_benchmarks.json` — 10 questions, pass gate ≥ 8/10.
- Benchmarks run: B01–B10 all 10/10 correct. Evidence: `evidence/genie/benchmark_run.json`, `space.json`, `prompting_note.md`; screenshot `evidence/screenshots/r6_genie_benchmarks.png`.

## R7 — Alert

Notebook: `R7_Alert`.

- `claims.analytics.weekly_rejection_rate` (Monday-start weeks, decided claims only) and the Databricks SQL alert `claims_weekly_rejection_alert`: MAX(rejection_rate) across plans for the fixed week of 2026-06-22, firing when > 0.18 (evaluated value 0.4 — SENIOR 2/5, SILVER_IND 1/5).

## R8 — Lakebase provider join

Notebook: `R8_Lakebase_Provider_Join`.

- Source: `claims_lakebase.public.provider_directory` — Lakebase Postgres catalog, 40 hospitals, `accredited_until` as native DATE.
- `claims.analytics.r8_provider_join`: 40 rows; 118 claims were admitted after the hospital's accreditation lapsed — HOS-024 43, HOS-035 34, HOS-009 33, HOS-005 8. Source note: `evidence/r8_source.md` (source: lakebase; earlier CSV fallback superseded); screenshot `evidence/screenshots/r8_lakebase_catalog.png`.

## R9 — Simpson's paradox

Notebook: `R9_Paradox`.

- `claims.analytics.r9_paradox` — 6 rows: HOS-017/HOS-022 × all/cashless/reimbursement rejection rates (rejected ÷ decided).
- Overall HOS-017 looks worse (0.21 vs 0.11), but within both claim types HOS-022 is higher (cashless 0.0625 vs 0.05; reimbursement 0.30 vs 0.25) — the claim-type mix is the confounder that reverses the ranking. Every row independently recomputed from `fact_claims` + `dim_hospital` and matched exactly.
- Insight memo: `evidence/r9_insight_memo.md`.

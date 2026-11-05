# Claims Lakehouse — Lakeflow Spark Declarative Pipeline

A medallion-architecture lakehouse for insurance claims, built as a single **Lakeflow Spark Declarative Pipeline** (formerly DLT) in SQL.

Raw CSV/JSON feeds land in a Unity Catalog volume, Auto Loader streams them into **bronze** streaming tables, **silver** applies deduplication + standardization + rule-based quarantine (plus an SCD Type 2 policy dimension via Auto CDC), and **gold** publishes an enriched claims fact and a hospital-monthly aggregate.

## Repository layout

```
<repo root>
├── 00_setup.ipynb                  # One-time UC setup: catalog, schemas, volume
├── hospital_monthly_designer.designer.ipynb  # Visual-pipeline prototype of hospital_monthly (WIP)
└── claims_pipeline/                # <-- you are here
    ├── README.md                   # this runbook
    ├── transformations/
    │   ├── bronze.sql   # 6 streaming tables via Auto Loader (read_files)
    │   ├── silver.sql   # scored views -> *_clean / *_quarantine MVs + policy_history SCD2
    │   └── gold.sql     # claims_enriched MV + hospital_monthly MV
    └── explorations/    # Ad-hoc analysis notebooks (quality checks, delta internals)
```

## How far the build got (commit map)

Each layer is a separate commit, so the commit history itself shows build progress:

| Commit | What it contains | Status |
| --- | --- | --- |
| 1. Bronze | `bronze.sql` — Auto Loader ingestion of all 6 sources | ✅ complete, verified |
| 2. Silver | `silver.sql` — dedup, standardization, Q-rule quarantine, policy SCD2 | ✅ complete, verified |
| 3. Gold | `gold.sql` — `claims_enriched` + `hospital_monthly` | ✅ complete, verified |
| 4. Explorations | Quality-check and Delta-internals notebooks | ✅ complete |
| 5. Setup + designer | `00_setup.ipynb`, hospital-monthly designer prototype | ⚠️ designer prototype only, not wired to a pipeline |
| 6. README | This runbook | ✅ current |

---

## Runbook — stand the lakehouse up from scratch

Every step ends with a **Verify** query; a step is only done when its verification returns the expected numbers (all counts below were verified on the live catalog at build time).

### Prerequisites

- A Databricks workspace with **Unity Catalog** enabled and **serverless** compute available (the pipeline runs on serverless with Photon).
- Permission to create a catalog, schemas, a volume, and a Lakeflow pipeline.
- The raw source files (CSV/JSON feeds) available locally to upload.

### Step 0 — Create catalog, schemas, and landing volume

Open `00_setup.ipynb` (repo root, one level above this folder) and run it with the notebook parameter **`catalog = claims`**. It executes:

```sql
create catalog claims;
use catalog claims;
create schema raw; create schema bronze; create schema silver; create schema gold;
create volume raw.landing;
```

**Verify:**

```sql
select catalog_name, schema_name from system.information_schema.schemata
where catalog_name = 'claims' and schema_name in ('raw','bronze','silver','gold');
-- expected: 4 rows
```

### Step 1 — Load raw feeds into the landing volume

Upload the raw feeds under `/Volumes/claims/raw/landing/`, one folder per source:

| Folder | Format | Notes |
| --- | --- | --- |
| `plans/` | CSV | header row, 4 rows |
| `members/` | CSV | 500 rows |
| `hospitals/` | CSV | 40 rows |
| `hospital_network_history/` | CSV | 41 rows |
| `claims/claims_raw/` | JSON | JSON-lines batch files (`batch_00*.json`); some rows carry an extra `channel` column |
| `policy_changes_cdc/` | JSON | CDC feed (`op`, `effective_from`, …) |

### Step 2 — Create and run the pipeline

Create a Lakeflow pipeline named **`claims_pipeline`** with exactly:

| Setting | Value | Why |
| --- | --- | --- |
| Source code | this repo's `claims_pipeline/transformations/` folder | files are `bronze.sql`, `silver.sql`, `gold.sql` |
| Catalog | `workspace` (top-level publish catalog) | avoids UC catalog-move restrictions on this workspace; actual targets are fully qualified |
| Schema | `default` | placeholder — SQL always qualifies targets with `${catalog}` |
| Configuration | `catalog = claims` | every table/volume reference resolves to `claims.<layer>.<table>` |
| Compute | Serverless, Photon ON, development mode OFF | as built |
| Trigger | Manual / job-triggered (not continuous) | as built |

Click **Start** and wait for all datasets to complete.

> Gotcha: `STREAM(read_files(...))` requires a **directory** path (never a single file), and CSV reads need `header => 'true'` — both already handled in `bronze.sql`.

### Step 3 — Verify bronze

```sql
select 'plans' src, count(*) n from claims.bronze.plans
union all select 'members', count(*) from claims.bronze.members
union all select 'hospitals', count(*) from claims.bronze.hospitals
union all select 'network_history', count(*) from claims.bronze.hospital_network_history
union all select 'claims', count(*) from claims.bronze.claims
union all select 'policy', count(*) from claims.bronze.policy
order by src;
-- expected: claims 3040 | hospitals 40 | members 500 | network_history 41 | plans 4 | policy 661
```

Every bronze row also carries `file_path` (`_metadata.file_path`) and `ingestion_ts` (`current_timestamp`); rescued values land in `_rescued_data` (e.g. claims rows with the extra `channel` column).

### Step 4 — Verify silver

```sql
select 'members_clean' t, count(*) n from claims.silver.members_clean
union all select 'members_quarantine', count(*) from claims.silver.members_quarantine
union all select 'hospitals_clean', count(*) from claims.silver.hospitals_clean
union all select 'hospitals_quarantine', count(*) from claims.silver.hospitals_quarantine
union all select 'plans_clean', count(*) from claims.silver.plans_clean
union all select 'plans_quarantine', count(*) from claims.silver.plans_quarantine
union all select 'network_history_clean', count(*) from claims.silver.hospital_network_history_clean
union all select 'network_history_quarantine', count(*) from claims.silver.hospital_network_history_quarantine
union all select 'claims_clean', count(*) from claims.silver.claims_clean
union all select 'claims_quarantine', count(*) from claims.silver.claims_quarantine
union all select 'policy_history', count(*) from claims.silver.policy_history
order by t;
-- expected: claims_clean 2974 | claims_quarantine 26 | hospitals_clean 40 | hospitals_quarantine 0
--           members_clean 500 | members_quarantine 0 | network_history_clean 41
--           network_history_quarantine 0 | plans_clean 4 | plans_quarantine 0 | policy_history 651
```

What silver does:

- **Deduplication**: latest version per key wins (ordered by `file_path` desc). For claims, only the latest version is judged — 3000 distinct claim_ids, 40 superseded drafts stay in bronze only.
- **Standardization**: trim, upper gender/plan code, lower email/city tier/plan family.
- **Rule-based quarantine**: each scored temp view computes `failed__rules ARRAY<STRING>`; rows with any rule land in `*_quarantine`, clean rows in `*_clean`. Rule codes: `MB-1..5` members, `HB-1..3` hospitals, `PB-1..5` plans, `NH-1..4` network history, `Q-A..Q-E` claims:
  - `Q-A` referential integrity (member/hospital/policy must exist, and the claim's member must own the policy)
  - `Q-B` date logic (admission after discharge, submitted after settled)
  - `Q-C` money logic (billed ≤ 0, approved negative or > billed)
  - `Q-D` status consistency (e.g. rejected without rejection code, settled without settlement ts)
  - `Q-E` room math (negative days/rent; rent × days > billed; room_days ≠ length of stay, with a same-day exception where `datediff = 0 and room_days = 1`)
- **Clean + quarantine = bronze** for claims: 2974 + 26 = 3040.
- **Policy SCD2**: `policy_history` via `AUTO CDC INTO ... STORED AS SCD TYPE 2`, sequenced by `effective_from` (not arrival order — the feed contains out-of-order updates). 651 versions (500 inserts + 151 updates; 10 deletes close versions only).

### Step 5 — Verify gold

```sql
select count(*) n, count(distinct claim_id) d from claims.gold.claims_enriched;
-- expected: n = 2974, d = 2974 (one row per clean claim)

select count(*) n, sum(claim_count) c from claims.gold.hospital_monthly;
-- expected: n = 468, c = 2974 (aggregate covers every enriched claim)
```

`claims_enriched` (clustered by `admission_month, hospital_id`) adds: `admission_month`, point-in-time `plan_code_at_admission` + `plan_family` + `room_rent_cap_per_day` (temporal join to the SCD2 policy history at admission), `policy_start_date`, `policy_tenure_months`, `length_of_stay`, `turnaround_days`, `room_rent_over_cap`, `is_network_at_admission` (network membership at admission), `hospital_city`, `hospital_city_tier`.

`hospital_monthly` per hospital × admission month: `claim_count`, `total_billed`, `total_approved` (never NULL — 0 when nothing approved), `rejected_count`.

### Step 6 — Watch data quality

In the pipeline's **Data quality** tab, the gate constraints on the claims flow (`q_a_referential_integrity` … `q_e_room_math`) log warn-level metrics per run, while routing stays controlled by `failed__rules`. Failing rows are never dropped silently — they always land in the matching `*_quarantine` table.

---

## Design notes / known gotchas

- All target tables are fully qualified with `${catalog}` (pipeline configuration `catalog = claims`), so the pipeline's top-level catalog setting is irrelevant to where data lands.
- `failed__rules` has a **double underscore** — per assignment spec.
- The SCD2 sequence column is `effective_from`; arrival order in the CDC feed is **not** trustworthy.
- `hospital_monthly_designer.designer.ipynb` is a visual-pipeline prototype of the same aggregate — not yet wired into a pipeline.

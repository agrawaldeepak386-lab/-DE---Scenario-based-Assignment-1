# R8 — provider join source record

**source: lakebase**.

* Input: the provider directory Postgres database (loaded from `provider_directory.sql` into the Lakebase project) registered as the Unity Catalog catalog **`claims_lakebase`**. Accreditation table: `claims_lakebase.public.provider_directory` — a FOREIGN table over Lakebase, 40 hospitals, `accredited_until` typed as DATE natively.
* Join: [R8_Lakebase_Provider_Join](#notebook-1176408995750750) cell "r8_provider_join table" reads `claims_lakebase.public.provider_directory` live from the notebook session and writes `claims.analytics.r8_provider_join` (40 rows, one per hospital).
* Screenshot: `evidence/screenshots/r8_lakebase_catalog.png` (catalog page for `claims_lakebase`).
* History: an earlier build used Fallback 2 (CSV twin `claims.raw.provider_directory` from `/Volumes/claims/raw/landing/provider_directory.csv`) because no Lakebase catalog existed yet; it is superseded by this Lakebase build and both produced identical verified results.
* One adaptation (applies on both paths): `fact_claims` carries `admission_date_key` (int `yyyyMMdd`) rather than a raw admission date, so the lapse comparison converts the key via `to_date(CAST(admission_date_key AS STRING), 'yyyyMMdd')`.

## Result summary

40 rows in `claims.analytics.r8_provider_join` (one per hospital). Claims admitted **after** accreditation lapsed, per hospital:

| hospital | accredited_until | claims_after_lapse |
| --- | --- | --- |
| HOS-024 Bengaluru Care Hospital 24 | 2025-12-16 | 43 |
| HOS-035 Mysuru Care Hospital 35 | 2026-01-31 | 34 |
| HOS-009 Jaipur Care Hospital 09 | 2025-12-25 | 33 |
| HOS-005 Mysuru Care Hospital 05 | 2026-05-25 | 8 |
| all 36 others | open / NONE | 0 |

Checks on the Lakebase-built table: 40 rows / 40 distinct hospitals; total after-lapse = 118 = 43+34+33+8; zero rows where `accredited_until` IS NULL but `claims_after_lapse` <> 0; column types exactly `hospital_id STRING, hospital_name STRING, city_tier STRING, accreditation STRING, accredited_until DATE, claims_after_lapse INT`. The same per-hospital values were independently re-counted from `fact_claims` + `dim_hospital` and matched the earlier CSV build, so the Lakebase source agrees with the CSV twin row for row.

-- Databricks notebook source
use catalog identifier(:target_catalog);

-- COMMAND ----------

-- DBTITLE 1,Data-quality checks
with latest as (
  select * from (
    select c.*, row_number() over (partition by claim_id order by file_path desc) rn
    from bronze.claims c
  ) where rn = 1
),
scored as (
  select
    (l.member_id is not null and mm.member_id is null)
      or (l.hospital_id is not null and hh.hospital_id is null)
      or (l.policy_id is not null and pp.policy_id is null)
      or (l.policy_id is not null and pm.policy_id is null) as qa,
    l.admission_date > l.discharge_date
      or (l.admission_date is not null and l.submitted_ts is not null
          and l.admission_date > to_date(l.submitted_ts))
      or (l.settled_ts is not null and l.submitted_ts is not null and l.submitted_ts > l.settled_ts)
      -- every populated date must fall inside the allowed claims window (mirrors silver.sql Q-B)
      or (l.admission_date is not null
          and (try_to_date(l.admission_date, 'yyyy-MM-dd') is null
               or try_to_date(l.admission_date, 'yyyy-MM-dd') not between date'2025-07-01' and date'2026-06-30'))
      or (l.discharge_date is not null
          and (try_to_date(l.discharge_date, 'yyyy-MM-dd') is null
               or try_to_date(l.discharge_date, 'yyyy-MM-dd') not between date'2025-07-01' and date'2026-06-30'))
      or (l.submitted_ts is not null
          and (to_date(l.submitted_ts) is null
               or to_date(l.submitted_ts) not between date'2025-07-01' and date'2026-06-30'))
      or (l.settled_ts is not null
          and (to_date(l.settled_ts) is null
               or to_date(l.settled_ts) not between date'2025-07-01' and date'2026-06-30')) as qb,
    l.billed_amount is null or l.billed_amount <= 0
      or l.approved_amount < 0 or l.approved_amount > l.billed_amount as qc,
    l.status is null or l.status not in ('submitted','approved','rejected','settled')
      or (l.status = 'approved' and l.approved_amount is null)
      or (l.status = 'rejected' and l.rejection_code is null)
      or (l.status = 'settled' and l.settled_ts is null)
      or (l.status = 'submitted'
          and (l.approved_amount is not null or l.rejection_code is not null or l.settled_ts is not null)) as qd,
    l.room_days < 0 or l.room_rent_per_day < 0
      or l.room_rent_per_day * l.room_days > l.billed_amount
      or (l.discharge_date is not null
          and l.room_days <> datediff(to_date(l.discharge_date), to_date(l.admission_date))
          and not (datediff(to_date(l.discharge_date), to_date(l.admission_date)) = 0
                   and l.room_days = 1)) as qe
  from latest l
  left join (select distinct member_id from bronze.members) mm on l.member_id = mm.member_id
  left join (select distinct hospital_id from bronze.hospitals) hh on l.hospital_id = hh.hospital_id
  left join (select distinct policy_id from silver.policy_history) pp on l.policy_id = pp.policy_id
  left join (select distinct policy_id, member_id from silver.policy_history) pm
    on l.policy_id = pm.policy_id and l.member_id = pm.member_id
),
expected as (
  select
    count(case when qa then 1 end) as qa_n,
    count(case when qb then 1 end) as qb_n,
    count(case when qc then 1 end) as qc_n,
    count(case when qd then 1 end) as qd_n,
    count(case when qe then 1 end) as qe_n
  from scored
),
quarantined as (
  select
    count(case when array_contains(failed__rules, 'Q-A') then 1 end) as qa_q,
    count(case when array_contains(failed__rules, 'Q-B') then 1 end) as qb_q,
    count(case when array_contains(failed__rules, 'Q-C') then 1 end) as qc_q,
    count(case when array_contains(failed__rules, 'Q-D') then 1 end) as qd_q,
    count(case when array_contains(failed__rules, 'Q-E') then 1 end) as qe_q
  from silver.claims_quarantine
)
select
  e.qa_n = q.qa_q as passes_q__a,
  e.qb_n = q.qb_q as passes_q__b,
  e.qc_n = q.qc_q as passes_q__c,
  e.qd_n = q.qd_q as passes_q__d,
  e.qe_n = q.qe_q as passes_q__e
from expected e cross join quarantined q

-- COMMAND ----------

-- DBTITLE 1,Set dq_problems task value (job plumbing)
-- MAGIC %python
-- MAGIC
-- MAGIC row = _sqldf.collect()[0]
-- MAGIC failed = [k for k, v in row.asDict().items() if k.startswith("passes_") and not v]
-- MAGIC dq_problems = len(failed)
-- MAGIC dbutils.jobs.taskValues.set(key="dq_problems", value=dq_problems)
-- MAGIC print(f"dq_problems = {dq_problems} (0 = healthy); failing rules: {failed or 'none'}")
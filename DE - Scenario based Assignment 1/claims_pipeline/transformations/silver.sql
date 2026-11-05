-------------------------------------------------------------------------------------
-----------------------------SILVER LAYER--------------------------------------------
-------------------------------------------------------------------------------------

-- ====================== members ======================
-- basic standardization: trim, upper gender, lower email; rules: MB-1 missing member_id,
-- MB-2 missing name, MB-3 unparseable dob, MB-4 invalid gender, MB-5 malformed email
create temporary view members_scored as
select
  f.* except (r1, r2, r3, r4, r5),
  filter(
    array('MB-1','MB-2','MB-3','MB-4','MB-5'),
    r -> case r
      when 'MB-1' then f.r1
      when 'MB-2' then f.r2
      when 'MB-3' then f.r3
      when 'MB-4' then f.r4
      when 'MB-5' then f.r5
    end
  ) as failed__rules
from (
  select
    c.*,
    c.member_id is null or trim(c.member_id) = '' as r1,
    c.name is null or trim(c.name) = '' as r2,
    c.dob is null or try_to_date(c.dob, 'yyyy-MM-dd') is null as r3,
    c.gender is null or upper(c.gender) not in ('M','F') as r4,
    c.email is null or c.email not like '%_@_%._%' as r5
  from (
    select * from (
      select *, row_number() over (partition by member_id order by file_path desc) rn
      from ${catalog}.bronze.members
    ) ranked where rn = 1
  ) c
) f;

create or refresh materialized view ${catalog}.silver.members_clean as
select
  member_id, trim(name) as name, dob, upper(trim(gender)) as gender, trim(city) as city,
  trim(state) as state, trim(national_id) as national_id, trim(phone) as phone,
  lower(trim(email)) as email, _rescued_data, file_path, ingestion_ts
from members_scored
where cardinality(failed__rules) = 0;

create or refresh materialized view ${catalog}.silver.members_quarantine as
select *
from members_scored
where cardinality(failed__rules) > 0;

-- ====================== hospitals ======================
-- basic standardization: trim, lower city_tier; rules: HB-1 missing hospital_id,
-- HB-2 missing name, HB-3 invalid city_tier
create temporary view hospitals_scored as
select
  f.* except (r1, r2, r3),
  filter(
    array('HB-1','HB-2','HB-3'),
    r -> case r
      when 'HB-1' then f.r1
      when 'HB-2' then f.r2
      when 'HB-3' then f.r3
    end
  ) as failed__rules
from (
  select
    c.*,
    c.hospital_id is null or trim(c.hospital_id) = '' as r1,
    c.name is null or trim(c.name) = '' as r2,
    c.city_tier is null or lower(c.city_tier) not in ('metro','non_metro') as r3
  from (
    select * from (
      select *, row_number() over (partition by hospital_id order by file_path desc) rn
      from ${catalog}.bronze.hospitals
    ) ranked where rn = 1
  ) c
) f;

create or refresh materialized view ${catalog}.silver.hospitals_clean as
select
  hospital_id, trim(name) as name, trim(city) as city, lower(trim(city_tier)) as city_tier,
  trim(state) as state, _rescued_data, file_path, ingestion_ts
from hospitals_scored
where cardinality(failed__rules) = 0;

create or refresh materialized view ${catalog}.silver.hospitals_quarantine as
select *
from hospitals_scored
where cardinality(failed__rules) > 0;

-- ====================== plans ======================
-- basic standardization: trim, upper plan_code, lower plan_family; rules: PB-1 missing plan_code,
-- PB-2 non-positive sum_insured, PB-3 copay_pct outside 0-100, PB-4 negative waiting periods,
-- PB-5 non-positive annual_premium
create temporary view plans_scored as
select
  f.* except (r1, r2, r3, r4, r5),
  filter(
    array('PB-1','PB-2','PB-3','PB-4','PB-5'),
    r -> case r
      when 'PB-1' then f.r1
      when 'PB-2' then f.r2
      when 'PB-3' then f.r3
      when 'PB-4' then f.r4
      when 'PB-5' then f.r5
    end
  ) as failed__rules
from (
  select
    c.*,
    c.plan_code is null or trim(c.plan_code) = '' as r1,
    c.sum_insured is null or c.sum_insured <= 0 as r2,
    c.copay_pct is null or c.copay_pct < 0 or c.copay_pct > 100 as r3,
    c.ped_waiting_months < 0 or c.initial_waiting_days < 0 as r4,
    c.annual_premium is null or c.annual_premium <= 0 as r5
  from (
    select * from (
      select *, row_number() over (partition by plan_code order by file_path desc) rn
      from ${catalog}.bronze.plans
    ) ranked where rn = 1
  ) c
) f;

create or refresh materialized view ${catalog}.silver.plans_clean as
select
  upper(trim(plan_code)) as plan_code, lower(trim(plan_family)) as plan_family,
  sum_insured, room_rent_cap_per_day, copay_pct, ped_waiting_months, initial_waiting_days,
  annual_premium, _rescued_data, file_path, ingestion_ts
from plans_scored
where cardinality(failed__rules) = 0;

create or refresh materialized view ${catalog}.silver.plans_quarantine as
select *
from plans_scored
where cardinality(failed__rules) > 0;

-- ====================== hospital_network_history ======================
-- basic standardization: trim; rules: NH-1 missing hospital_id, NH-2 unparseable network_from,
-- NH-3 unparseable network_to (NULL = open-ended, allowed), NH-4 network_to before network_from
create temporary view network_history_scored as
select
  f.* except (r1, r2, r3, r4),
  filter(
    array('NH-1','NH-2','NH-3','NH-4'),
    r -> case r
      when 'NH-1' then f.r1
      when 'NH-2' then f.r2
      when 'NH-3' then f.r3
      when 'NH-4' then f.r4
    end
  ) as failed__rules
from (
  select
    c.*,
    c.hospital_id is null or trim(c.hospital_id) = '' as r1,
    c.network_from is null or try_to_date(c.network_from, 'yyyy-MM-dd') is null as r2,
    c.network_to is not null and try_to_date(c.network_to, 'yyyy-MM-dd') is null as r3,
    try_to_date(c.network_from, 'yyyy-MM-dd') is not null
      and try_to_date(c.network_to, 'yyyy-MM-dd') is not null
      and try_to_date(c.network_to, 'yyyy-MM-dd') < try_to_date(c.network_from, 'yyyy-MM-dd') as r4
  from (
    select * from (
      select *, row_number() over (partition by hospital_id, network_from order by file_path desc) rn
      from ${catalog}.bronze.hospital_network_history
    ) ranked where rn = 1
  ) c
) f;

create or refresh materialized view ${catalog}.silver.hospital_network_history_clean as
select
  trim(hospital_id) as hospital_id, network_from, network_to, _rescued_data, file_path, ingestion_ts
from network_history_scored
where cardinality(failed__rules) = 0;

create or refresh materialized view ${catalog}.silver.hospital_network_history_quarantine as
select *
from network_history_scored
where cardinality(failed__rules) > 0;

-- only the latest version of each claim is judged (resubmitted claims are judged on
-- their latest version, not an earlier draft); failed__rules only ever holds Q-codes.
-- Superseded drafts (rn > 1) stay only in bronze - they are not clean or quarantined.
create temporary view claims_scored as
select
  f.*,
  filter(
    array('Q-A','Q-B','Q-C','Q-D','Q-E'),
    r -> case r
      when 'Q-A' then f.qa_flag
      when 'Q-B' then f.qb_flag
      when 'Q-C' then f.qc_flag
      when 'Q-D' then f.qd_flag
      when 'Q-E' then f.qe_flag
    end
  ) as failed__rules
from (
  select
    c.*,
    (c.member_id is not null and mm.member_id is null)
      or (c.hospital_id is not null and hh.hospital_id is null)
      or (c.policy_id is not null and pp.policy_id is null)
      -- the claim's member must actually own the policy (pair must exist in the policy feed)
      or (c.policy_id is not null and pm.policy_id is null) as qa_flag,
    c.admission_date > c.discharge_date
      or (c.settled_ts is not null and c.submitted_ts is not null and c.submitted_ts > c.settled_ts) as qb_flag,
    c.billed_amount is null or c.billed_amount <= 0
      or c.approved_amount < 0
      or c.approved_amount > c.billed_amount as qc_flag,
    c.status is null
      or c.status not in ('submitted','approved','rejected','settled')
      or (c.status = 'approved' and c.approved_amount is null)
      or (c.status = 'rejected' and c.rejection_code is null)
      or (c.status = 'settled' and c.settled_ts is null)
      or (c.status = 'submitted'
          and (c.approved_amount is not null or c.rejection_code is not null or c.settled_ts is not null)) as qd_flag,
    c.room_days < 0 or c.room_rent_per_day < 0
      or c.room_rent_per_day * c.room_days > c.billed_amount
      -- strict stay check: billed room-days must equal the actual stay length,
      -- except same-day stays (admission and discharge on the same date count as 1 room day)
      or (c.discharge_date is not null
          and c.room_days <> datediff(to_date(c.discharge_date), to_date(c.admission_date))
          and not (datediff(to_date(c.discharge_date), to_date(c.admission_date)) = 0
                   and c.room_days = 1)) as qe_flag
  from (
    select * from (
      select *, row_number() over (partition by claim_id order by file_path desc) rn
      from ${catalog}.bronze.claims
    ) ranked where rn = 1
  ) c
  left join (select distinct member_id from ${catalog}.bronze.members) mm on c.member_id = mm.member_id
  left join (select distinct hospital_id from ${catalog}.bronze.hospitals) hh on c.hospital_id = hh.hospital_id
  left join (select distinct policy_id from ${catalog}.bronze.policy) pp on c.policy_id = pp.policy_id
  left join (select distinct policy_id, member_id from ${catalog}.bronze.policy) pm
    on c.policy_id = pm.policy_id and c.member_id = pm.member_id
) f;


create or refresh private materialized view ${catalog}.silver.claims_clean_gated (
  constraint q_a_referential_integrity expect (qa_flag is not true),
  constraint q_b_date_ordering expect (qb_flag is not true),
  constraint q_c_amount_sanity expect (qc_flag is not true),
  constraint q_d_status_consistency expect (qd_flag is not true),
  constraint q_e_room_math expect (qe_flag is not true)
) as
select * from claims_scored;

create or refresh materialized view ${catalog}.silver.claims_clean as
select * except (rn, qa_flag, qb_flag, qc_flag, qd_flag, qe_flag, failed__rules)
from ${catalog}.silver.claims_clean_gated
where cardinality(failed__rules) = 0;


create or refresh materialized view ${catalog}.silver.claims_quarantine as
select * except (rn, qa_flag, qb_flag, qc_flag, qd_flag, qe_flag)
from claims_scored
where cardinality(failed__rules) > 0;


create temporary view policy_changes as
select
  policy_id,
  member_id,
  plan_code,
  to_date(effective_from, 'yyyy-MM-dd') as effective_from,
  op
from stream(${catalog}.bronze.policy);


create or refresh streaming table ${catalog}.silver.policy_history;

create flow policy_history_cdc as auto cdc into ${catalog}.silver.policy_history
from stream(policy_changes)
keys (policy_id)
apply as delete when op = 'DELETE'
sequence by effective_from
columns * except (op, effective_from)
stored as scd type 2;

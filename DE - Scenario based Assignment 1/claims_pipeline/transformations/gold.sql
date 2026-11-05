-------------------------------------------------------------------------------------
-----------------------------GOLD LAYER----------------------------------------------
-------------------------------------------------------------------------------------

-- policy dimension helpers: point-in-time plan at admission + overall policy start date
create temporary view policy_start as
select
  policy_id,
  member_id,
  min(__START_AT) as policy_start_date
from ${catalog}.silver.policy_history
group by policy_id, member_id;

-- aggregated to one row per claim so overlapping network periods cannot duplicate rows;
-- the max() over a left join coalesces to false, so the flag is never empty
create temporary view network_membership as
select
  c.claim_id,
  max(case when nh.hospital_id is not null then true else false end) as is_network_at_admission
from ${catalog}.silver.claims_clean c
left join ${catalog}.silver.hospital_network_history_clean nh
  on nh.hospital_id = c.hospital_id
 and to_date(nh.network_from) <= to_date(c.admission_date)
 and (nh.network_to is null or to_date(nh.network_to) >= to_date(c.admission_date))
group by c.claim_id;

create or refresh materialized view ${catalog}.gold.claims_enriched
CLUSTER BY (admission_month, hospital_id)
as
select
  c.claim_id,
  c.member_id,
  c.policy_id,
  c.hospital_id,
  c.admission_date,
  c.discharge_date,
  trunc(to_date(c.admission_date), 'MONTH') as admission_month,
  c.diagnosis_code,
  c.procedure_code,
  c.is_pre_existing,
  c.claim_type,
  c.billed_amount,
  c.room_rent_per_day,
  c.room_days,
  c.status,
  c.approved_amount,
  c.rejection_code,
  c.submitted_ts,
  c.settled_ts,
  c.channel,
  ph.plan_code as plan_code_at_admission,
  p.plan_family,
  p.room_rent_cap_per_day,
  ps.policy_start_date,
  cast(months_between(to_date(c.admission_date), ps.policy_start_date) as int) as policy_tenure_months,
  cast(datediff(to_date(c.discharge_date), to_date(c.admission_date)) as int) as length_of_stay,
  case
    when c.settled_ts is not null and c.submitted_ts is not null
      then datediff(cast(c.settled_ts as timestamp), cast(c.submitted_ts as timestamp))
  end as turnaround_days,
  c.room_rent_per_day > try_cast(p.room_rent_cap_per_day as double) as room_rent_over_cap,
  nm.is_network_at_admission,
  h.city as hospital_city,
  h.city_tier as hospital_city_tier
from ${catalog}.silver.claims_clean c
left join ${catalog}.silver.policy_history ph
  on ph.policy_id = c.policy_id
 and ph.member_id = c.member_id
 and ph.__START_AT <= to_date(c.admission_date)
 and (ph.__END_AT is null or ph.__END_AT > to_date(c.admission_date))
left join ${catalog}.silver.plans_clean p
  on p.plan_code = upper(ph.plan_code)
left join ${catalog}.silver.hospitals_clean h
  on h.hospital_id = c.hospital_id
left join policy_start ps
  on ps.policy_id = c.policy_id
 and ps.member_id = c.member_id
left join network_membership nm
  on nm.claim_id = c.claim_id;

-- hospital monthly aggregates off the enriched claims:
-- total_approved is 0 (never empty) when a month has no approved amounts
create or refresh materialized view ${catalog}.gold.hospital_monthly as
select
  hospital_id,
  admission_month,
  cast(count(*) as int) as claim_count,
  cast(sum(billed_amount) as decimal(18,2)) as total_billed,
  cast(coalesce(sum(approved_amount), 0) as decimal(18,2)) as total_approved,
  cast(sum(case when status = 'rejected' then 1 else 0 end) as int) as rejected_count
from ${catalog}.gold.claims_enriched
group by hospital_id, admission_month;

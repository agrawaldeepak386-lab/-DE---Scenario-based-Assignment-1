'''Single source of truth for the claims quarantine rules (Q-A .. Q-E).

Each rule is declared once here as (code, name, description, SQL predicate).
A predicate is a boolean SQL expression evaluated over these aliases:

  c  : the latest version of each claim (one row per claim_id, deduplicated
       by row_number() over (partition by claim_id order by file_path desc))
  mm : distinct member_id existing in bronze.members
  hh : distinct hospital_id existing in bronze.hospitals
  pp : distinct policy_id existing in silver.policy_history
  pm : distinct (policy_id, member_id) pair existing in silver.policy_history

The authoritative enforcement lives in
`DE - Scenario based Assignment 1/claims_pipeline/transformations/silver.sql`
(claims_scored -> claims_clean_gated -> claims_clean / claims_quarantine); the
pipeline imports this module to materialize the quarantine-rule audit dataset
(claims_quarantine_audit.py) so rule definitions are not copy-pasted there.
Quality_checks (the job dq_check task) independently re-scores bronze and
compares against claims_quarantine - three vantage points over one rule set.
'''

CLAIMS_QUARANTINE_RULES = [
    {
        'code': 'Q-A',
        'name': 'referential integrity',
        'description': (
            'referenced member / hospital / policy must exist, and the claim\'s '
            'member must actually own the referenced policy'
        ),
        'predicate': '''
      (c.member_id is not null and mm.member_id is null)
      or (c.hospital_id is not null and hh.hospital_id is null)
      or (c.policy_id is not null and pp.policy_id is null)
      or (c.policy_id is not null and pm.policy_id is null)
''',
    },
    {
        'code': 'Q-B',
        'name': 'date ordering + window',
        'description': (
            'admission <= discharge, admission on/before submission, '
            'submission on/before settlement, and every populated date inside '
            'the allowed claims window 2025-07-01 .. 2026-06-30; unparseable '
            'populated dates also fail (nulls allowed)'
        ),
        'predicate': '''
      c.admission_date > c.discharge_date
      or (c.admission_date is not null and c.submitted_ts is not null
          and c.admission_date > to_date(c.submitted_ts))
      or (c.settled_ts is not null and c.submitted_ts is not null and c.submitted_ts > c.settled_ts)
      or (c.admission_date is not null
          and (try_to_date(c.admission_date, 'yyyy-MM-dd') is null
               or try_to_date(c.admission_date, 'yyyy-MM-dd') not between date'2025-07-01' and date'2026-06-30'))
      or (c.discharge_date is not null
          and (try_to_date(c.discharge_date, 'yyyy-MM-dd') is null
               or try_to_date(c.discharge_date, 'yyyy-MM-dd') not between date'2025-07-01' and date'2026-06-30'))
      or (c.submitted_ts is not null
          and (to_date(c.submitted_ts) is null
               or to_date(c.submitted_ts) not between date'2025-07-01' and date'2026-06-30'))
      or (c.settled_ts is not null
          and (to_date(c.settled_ts) is null
               or to_date(c.settled_ts) not between date'2025-07-01' and date'2026-06-30'))
''',
    },
    {
        'code': 'Q-C',
        'name': 'amount sanity',
        'description': 'billed amount positive, approved amount non-negative and <= billed',
        'predicate': '''
      c.billed_amount is null or c.billed_amount <= 0
      or c.approved_amount < 0
      or c.approved_amount > c.billed_amount
''',
    },
    {
        'code': 'Q-D',
        'name': 'status consistency',
        'description': (
            'status in (submitted, approved, rejected, settled) and the fields '
            'present for each status are consistent (approved_amount, '
            'rejection_code, settled_ts)'
        ),
        'predicate': '''
      c.status is null
      or c.status not in ('submitted','approved','rejected','settled')
      or (c.status = 'approved' and c.approved_amount is null)
      or (c.status = 'rejected' and c.rejection_code is null)
      or (c.status = 'settled' and c.settled_ts is null)
      or (c.status = 'submitted'
          and (c.approved_amount is not null or c.rejection_code is not null or c.settled_ts is not null))
''',
    },
    {
        'code': 'Q-E',
        'name': 'room math',
        'description': (
            'room days / rates non-negative, room cost within the billed '
            'amount, and billed room-days equal the actual stay length '
            '(same-day stays count as 1 room day)'
        ),
        'predicate': '''
      c.room_days < 0 or c.room_rent_per_day < 0
      or c.room_rent_per_day * c.room_days > c.billed_amount
      or (c.discharge_date is not null
          and c.room_days <> datediff(to_date(c.discharge_date), to_date(c.admission_date))
          and not (datediff(to_date(c.discharge_date), to_date(c.admission_date)) = 0
                   and c.room_days = 1))
''',
    },
]


def rule_codes():
    '''Rule codes in canonical order, e.g. [Q-A, Q-B, Q-C, Q-D, Q-E].'''
    return [rule['code'] for rule in CLAIMS_QUARANTINE_RULES]


def failed_rules_expression(codes=None):
    '''Return the SQL filter(array(...), ...) expression that turns the
    per-rule flags into the failed__rules array, mirroring silver.sql.
    `codes` defaults to the canonical rule order.'''
    codes = codes or rule_codes()
    when_branches = '\n      '.join(
        "when '{code}' then f.{flag}".format(code=code, flag=code.lower().replace('-', '_') + '_flag')
        for code in codes
    )
    code_list = ','.join("'{}'".format(code) for code in codes)
    return '''
    filter(
      array({code_list}),
      r -> case r
      {when_branches}
    end
  ) as failed__rules
'''.format(code_list=code_list, when_branches=when_branches)

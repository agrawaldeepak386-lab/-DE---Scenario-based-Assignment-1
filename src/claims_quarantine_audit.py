'''Quarantine-rule audit dataset for the claims pipeline.

This Python source is part of the claims_lakehouse_pipeline (see
resources/claims_lakehouse_pipeline.pipeline.yml). It imports the
quarantine-rules module (src/quarantine_rules.py) and materializes one
materialized view: <target_catalog>.silver.claims_quarantine_rule_audit, with
one row per rule:

  rule_code         Q-A .. Q-E
  rule_name         short human label
  violating_rows    latest-version claims failing the module predicate
  quarantined_rows  rows claims_quarantine holds for this rule
  in_sync           violating_rows == quarantined_rows

silver.sql remains the enforcement (it gates and quarantines); this audit is
an independent recount of the same rules so drift between rule definition and
enforcement shows up as in_sync = false. It is read-only with respect to the
quarantine decision - no pipeline logic changes.
'''

import sys
from pathlib import Path

# Make the sibling quarantine-rules module importable outside the pipeline
# (pipeline Python files do not automatically share an import root).
# Pipeline library files have no __file__, but are importable by module name
# inside the pipeline, so the plain import below works there on its own.
try:
    sys.path.append(str(Path(__file__).resolve().parent))
except NameError:
    pass

from pyspark import pipelines as dp
from pyspark.sql import functions as F
from pyspark.sql.window import Window

# Pipeline configuration (resources/claims_lakehouse_pipeline.pipeline.yml)
# is surfaced to Python sources through Spark conf.
try:
    TARGET_CATALOG = spark.conf.get('target_catalog', 'claims')
except Exception:
    # Outside the pipeline (Serverless / ad-hoc evaluation) only specific
    # conf keys are readable via spark.conf.get(); fall back to the same
    # default the pipeline configuration carries.
    TARGET_CATALOG = 'claims'


def _claim_rules():
    '''Return the quarantine-rule definitions from the sibling module.

    Resolved lazily (not at module top level) because pipeline Python files
    run without __file__/sys.path guarantees: when the plain import works it
    is used; otherwise the module's top-level names are picked up from the
    shared namespace all pipeline Python sources execute in (the import is
    attempted inside the function, after every source file has run).
    '''
    try:
        import quarantine_rules as qr
        return qr.CLAIMS_QUARANTINE_RULES
    except ImportError:
        return CLAIMS_QUARANTINE_RULES


def _scored_latest_claims():
    '''Latest version of each claim joined to the existence lookup aliases
    (c / mm / hh / pp / pm) that the module predicates are written against -
    the same shape silver.sql gives claims_scored.'''
    claims = spark.read.table('bronze.claims')  # same-pipeline dataset (bronze.sql)
    latest = (
        claims.select(F.col('*'), F.row_number().over(
            Window.partitionBy('claim_id').orderBy(F.col('file_path').desc())).alias('rn'))
        .where(F.col('rn') == 1)
        .alias('c')
    )
    members = spark.read.table('bronze.members').select('member_id').distinct().alias('mm')
    hospitals = spark.read.table('bronze.hospitals').select('hospital_id').distinct().alias('hh')
    policy_history = spark.read.table('silver.policy_history')  # same-pipeline dataset
    pp = policy_history.select('policy_id').distinct().alias('pp')
    pm = policy_history.select('policy_id', 'member_id').distinct().alias('pm')

    return (
        latest
        .join(members, F.col('c.member_id') == F.col('mm.member_id'), 'left')
        .join(hospitals, F.col('c.hospital_id') == F.col('hh.hospital_id'), 'left')
        .join(pp, F.col('c.policy_id') == F.col('pp.policy_id'), 'left')
        .join(pm, (F.col('c.policy_id') == F.col('pm.policy_id'))
                & (F.col('c.member_id') == F.col('pm.member_id')), 'left')
    )


def _stack_rules(counts_df, column_map):
    '''Reshape one row of per-rule counts (one column per rule code) into one
    row per rule: (rule_code, <measure>).'''
    n = len(column_map)
    pairs = ', '.join("'{code}', `{col}`".format(code=code, col=col)
                      for code, col in column_map)
    return counts_df.select(
        F.expr('stack({n}, {pairs}) as (rule_code, measure)'.format(n=n, pairs=pairs))
    )


@dp.materialized_view(
    name=TARGET_CATALOG + '.silver.claims_quarantine_rule_audit',
    comment=('Per-rule quarantine audit over the latest claim versions. '
             'violating_rows re-scores the quarantine-rules module predicates '
             'independently of silver.sql; quarantined_rows counts what '
             'claims_quarantine actually holds; in_sync must stay true.'),
)
def claims_quarantine_rule_audit():
    rules = _claim_rules()
    codes = [r['code'] for r in rules]

    # Independent recount from the module predicates (latest claims only).
    violating_exprs = [
        F.count(F.when(F.expr(r['predicate']), True)).alias(r['code'])
        for r in rules
    ]
    violating = _stack_rules(
        _scored_latest_claims().agg(*violating_exprs),
        list(zip(codes, codes)),
    )

    # What the enforced quarantine view actually holds, per rule.
    quarantined = spark.read.table('silver.claims_quarantine')  # same-pipeline dataset (silver.sql)
    quarantined_exprs = [
        F.count(F.when(F.array_contains('failed__rules', code), True)).alias(code)
        for code in codes
    ]
    quarantined_counts = _stack_rules(
        quarantined.agg(*quarantined_exprs),
        list(zip(codes, codes)),
    )

    names = {r['code']: r['name'] for r in rules}
    name_col = F.create_map([F.lit(x) for kv in names.items() for x in kv])

    return (
        violating.alias('v')
        .join(quarantined_counts.alias('q'), 'rule_code')
        .select(
            F.col('rule_code'),
            name_col[F.col('rule_code')].alias('rule_name'),
            F.col('v.measure').cast('bigint').alias('violating_rows'),
            F.col('q.measure').cast('bigint').alias('quarantined_rows'),
            (F.col('v.measure') == F.col('q.measure')).alias('in_sync'),
        )
        .orderBy('rule_code')
    )

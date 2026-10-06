USE ROLE ACCOUNTADMIN;
USE WAREHOUSE DENIAL_WH;

CREATE OR REPLACE SEMANTIC VIEW DENIAL_ANALYTICS_DB.ANALYTICS.DENIAL_SEMANTIC_VIEW

  TABLES (
    claims AS DENIAL_ANALYTICS_DB.MODELED.FACT_CLAIMS
      PRIMARY KEY (claim_id)
      WITH SYNONYMS ('medical claims', 'submitted claims')
      COMMENT = 'One row per medical claim with payer, procedure, outcome and denial details',
    appeal_queue AS DENIAL_ANALYTICS_DB.ANALYTICS.APPEAL_PRIORITY_QUEUE
      PRIMARY KEY (claim_id)
      WITH SYNONYMS ('appeal list', 'work queue', 'claims to appeal')
      COMMENT = 'Denied, appealable claims ranked by net expected recovery. Rank 1 = work first',
    risk AS DENIAL_ANALYTICS_DB.ANALYTICS.DENIAL_RISK_SCORES
      PRIMARY KEY (claim_id)
      COMMENT = 'Model-predicted probability (0 to 1) that a claim gets denied'
  )

  RELATIONSHIPS (
    queue_to_claims AS appeal_queue (claim_id) REFERENCES claims,
    risk_to_claims  AS risk (claim_id) REFERENCES claims
  )

  FACTS (
    claims.claim_amount       AS claims.claim_amount_usd
      COMMENT = 'Billed amount of one claim in USD',
    appeal_queue.claim_net_value AS appeal_queue.net_value_usd
      COMMENT = 'Expected recovery minus work cost for one claim in USD'
  )

  DIMENSIONS (
    claims.claim_number     AS claims.claim_id,
    claims.submission_date  AS claims.claim_submission_date,
    claims.submission_year  AS claims.claim_year,
    claims.payer            AS claims.payer_type
      WITH SYNONYMS = ('insurer', 'insurance company', 'payer type'),
    claims.specialty        AS claims.provider_specialty
      WITH SYNONYMS = ('provider specialty', 'department'),
    claims.procedure_code   AS claims.cpt_code
      WITH SYNONYMS = ('CPT', 'CPT code'),
    claims.diagnosis_code   AS claims.icd10_code
      WITH SYNONYMS = ('ICD-10', 'diagnosis'),
    claims.claim_outcome    AS claims.outcome
      COMMENT = 'One of: paid, denied, partial_pay, pending',
    claims.denial_reason    AS claims.denial_category
      COMMENT = 'One of: medical_necessity, coding_error, auth_missing, eligibility, duplicate, timely_filing, bundling',
    claims.denial_code      AS claims.denial_reason_code
      WITH SYNONYMS = ('CARC', 'denial code'),
    appeal_queue.work_tier_name AS appeal_queue.work_tier
      COMMENT = 'Fast-track (simple resubmit) or Formal appeal',
    appeal_queue.priority_number AS appeal_queue.priority_rank
      COMMENT = '1 = highest priority to work',
    risk.denial_risk        AS risk.denial_risk_score
      WITH SYNONYMS = ('risk score', 'denial probability')
  )

  METRICS (
    claims.total_claims   AS COUNT(claims.claim_id),
    claims.denied_claims  AS SUM(claims.is_denied)
      COMMENT = 'Number of denied claims',
    claims.denial_rate    AS AVG(claims.is_denied)
      COMMENT = 'Share of decided claims that were denied; pending claims excluded',
    claims.billed_dollars AS SUM(claims.claim_amount_usd),
    claims.denied_dollars AS SUM(IFF(claims.is_denied = 1, claims.claim_amount_usd, 0))
      COMMENT = 'Total billed dollars on denied claims',
    appeal_queue.expected_recovery_dollars AS SUM(appeal_queue.expected_recovery_usd),
    appeal_queue.net_recovery_dollars      AS SUM(appeal_queue.net_value_usd)
      COMMENT = 'Expected recovery after subtracting work cost',
    risk.average_denial_risk AS AVG(risk.denial_risk_score)
  )

  COMMENT = 'Claim denial risk and appeal prioritization (synthetic DenialIQ data)';

  SELECT * FROM SEMANTIC_VIEW(
  DENIAL_ANALYTICS_DB.ANALYTICS.DENIAL_SEMANTIC_VIEW
  METRICS claims.denial_rate, claims.denied_dollars
  DIMENSIONS claims.payer
);
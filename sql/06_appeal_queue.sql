USE WAREHOUSE DENIAL_WH;
USE SCHEMA DENIAL_ANALYTICS_DB.ANALYTICS;

CREATE OR REPLACE TABLE APPEAL_PRIORITY_QUEUE AS
SELECT
  claim_id,
  claim_submission_date,
  payer_type,
  denial_reason_code,
  denial_category,
  recovery_action,
  claim_amount_usd,
  appeal_success_probability,
  CASE WHEN recovery_action IN ('recode_and_resubmit','verify_eligibility_resubmit')
       THEN 'Fast-track' ELSE 'Formal appeal' END              AS work_tier,
  CASE WHEN recovery_action IN ('recode_and_resubmit','verify_eligibility_resubmit')
       THEN 25 ELSE 118 END                                     AS est_work_cost_usd,
  ROUND(claim_amount_usd * appeal_success_probability, 2)       AS expected_recovery_usd,
  ROUND(claim_amount_usd * appeal_success_probability - est_work_cost_usd, 2) AS net_value_usd,
  ROW_NUMBER() OVER (ORDER BY net_value_usd DESC)               AS priority_rank
FROM DENIAL_ANALYTICS_DB.MODELED.FACT_CLAIMS
WHERE is_denied = 1
  AND appealable = TRUE;

-- Headline result: work the top 1,000 by priority vs. oldest-first
WITH ranked AS (
  SELECT net_value_usd,
         priority_rank,
         ROW_NUMBER() OVER (ORDER BY claim_submission_date) AS fifo_rank
  FROM APPEAL_PRIORITY_QUEUE
)
SELECT
  ROUND(SUM(IFF(priority_rank <= 1000, net_value_usd, 0))) AS top_1000_by_priority,
  ROUND(SUM(IFF(fifo_rank     <= 1000, net_value_usd, 0))) AS top_1000_oldest_first
FROM ranked;
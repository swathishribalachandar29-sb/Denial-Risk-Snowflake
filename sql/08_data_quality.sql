USE WAREHOUSE DENIAL_WH;
USE DATABASE DENIAL_ANALYTICS_DB;

CREATE OR REPLACE VIEW ANALYTICS.DATA_QUALITY_CHECKS AS
WITH checks AS (
  -- UNIQUE
  SELECT 'unique' AS check_type, 'claim_id is unique in FACT_CLAIMS' AS check_name,
         COUNT(*) - COUNT(DISTINCT claim_id) AS failing_rows
  FROM MODELED.FACT_CLAIMS
  UNION ALL
  -- NOT NULL
  SELECT 'not_null', 'required fields are filled',
         COUNT_IF(claim_id IS NULL OR payer_type IS NULL OR cpt_code IS NULL
                  OR outcome IS NULL OR claim_amount_usd IS NULL)
  FROM MODELED.FACT_CLAIMS
  UNION ALL
  -- REFERENTIAL INTEGRITY (orphans)
  SELECT 'relationships', 'every payer exists in DIM_PAYER',
         COUNT(*) FROM MODELED.FACT_CLAIMS f
         LEFT JOIN MODELED.DIM_PAYER d ON f.payer_type = d.payer_type
         WHERE d.payer_type IS NULL
  UNION ALL
  SELECT 'relationships', 'every CPT exists in DIM_PROCEDURE',
         COUNT(*) FROM MODELED.FACT_CLAIMS f
         LEFT JOIN MODELED.DIM_PROCEDURE d ON f.cpt_code = d.cpt_code
         WHERE d.cpt_code IS NULL
  UNION ALL
  SELECT 'relationships', 'every denial code exists in DIM_DENIAL_REASON',
         COUNT(*) FROM MODELED.FACT_CLAIMS f
         LEFT JOIN MODELED.DIM_DENIAL_REASON d ON f.denial_reason_code = d.denial_reason_code
         WHERE f.denial_reason_code IS NOT NULL AND d.denial_reason_code IS NULL
  UNION ALL
  -- ACCEPTED VALUES
  SELECT 'accepted_values', 'outcome is paid/denied/partial_pay/pending',
         COUNT_IF(outcome NOT IN ('paid','denied','partial_pay','pending'))
  FROM MODELED.FACT_CLAIMS
  UNION ALL
  SELECT 'accepted_values', 'only denied claims have a denial code',
         COUNT_IF((outcome = 'denied') <> (denial_reason_code IS NOT NULL))
  FROM MODELED.FACT_CLAIMS
  UNION ALL
  -- RANGE
  SELECT 'range', 'claim amount is above 0',
         COUNT_IF(claim_amount_usd <= 0) FROM MODELED.FACT_CLAIMS
  UNION ALL
  SELECT 'range', 'documentation score is between 0 and 1',
         COUNT_IF(documentation_completeness NOT BETWEEN 0 AND 1) FROM MODELED.FACT_CLAIMS
  UNION ALL
  SELECT 'range', 'risk score is between 0 and 1',
         COUNT_IF(denial_risk_score NOT BETWEEN 0 AND 1) FROM ANALYTICS.DENIAL_RISK_SCORES
  UNION ALL
  -- RECONCILIATION
  SELECT 'reconciliation', 'every claim got a risk score',
         ABS((SELECT COUNT(*) FROM MODELED.FACT_CLAIMS)
           - (SELECT COUNT(*) FROM ANALYTICS.DENIAL_RISK_SCORES))
  UNION ALL
  SELECT 'reconciliation', 'denied claims = rows in denial labels',
         ABS((SELECT COUNT_IF(outcome = 'denied') FROM MODELED.FACT_CLAIMS)
           - (SELECT COUNT(*) FROM RAW.RAW_DENIAL_LABELS))
  UNION ALL
  SELECT 'reconciliation', 'appeal queue = denied claims marked appealable',
         ABS((SELECT COUNT_IF(is_denied = 1 AND appealable) FROM MODELED.FACT_CLAIMS)
           - (SELECT COUNT(*) FROM ANALYTICS.APPEAL_PRIORITY_QUEUE))
)
SELECT check_type, check_name, failing_rows,
       IFF(failing_rows = 0, 'PASS', 'FAIL') AS status,
       CURRENT_TIMESTAMP() AS checked_at
FROM checks;

SELECT * FROM ANALYTICS.DATA_QUALITY_CHECKS ORDER BY status, check_type;
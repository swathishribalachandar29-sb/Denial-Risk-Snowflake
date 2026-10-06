USE WAREHOUSE DENIAL_WH;
USE SCHEMA DENIAL_ANALYTICS_DB.MODELED;

-- Q1: Overall denial rate and $ denied
SELECT
  COUNT(*) AS total_claims,
  SUM(is_denied)AS denied_claims,
  ROUND(AVG(is_denied) * 100, 1)AS denial_rate_pct,
  ROUND(SUM(IFF(is_denied = 1, claim_amount_usd, 0)), 0) AS dollars_denied
FROM FACT_CLAIMS
WHERE is_denied IS NOT NULL;

-- Q2: Denial rate by payer
SELECT
  payer_type,
  COUNT(*) AS claims,
  ROUND(AVG(is_denied) * 100, 1) AS denial_rate_pct,
  ROUND(SUM(IFF(is_denied = 1, claim_amount_usd, 0)), 0) AS dollars_denied
FROM FACT_CLAIMS
WHERE is_denied IS NOT NULL
GROUP BY payer_type
ORDER BY denial_rate_pct DESC;

-- Q3: $ denied by denial reason
SELECT
  denial_category,
  COUNT(*) AS denied_claims,
  ROUND(SUM(claim_amount_usd), 0) AS dollars_denied
FROM FACT_CLAIMS
WHERE is_denied = 1
GROUP BY denial_category
ORDER BY dollars_denied DESC;
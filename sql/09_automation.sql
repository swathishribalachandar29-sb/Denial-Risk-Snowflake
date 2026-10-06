USE ROLE ACCOUNTADMIN;
USE WAREHOUSE DENIAL_WH;
USE DATABASE DENIAL_ANALYTICS_DB;

-- Change tracker on the raw claims table
CREATE OR REPLACE STREAM RAW.RAW_CLAIMS_STREAM ON TABLE RAW.RAW_CLAIMS;

-- Log table: one row per pipeline run
CREATE TABLE IF NOT EXISTS ANALYTICS.PIPELINE_LOG (
  run_at TIMESTAMP_LTZ,
  rows_changed INT
);

-- Task 1 (root): runs every 5 min, but ONLY if new data arrived
CREATE OR REPLACE TASK ANALYTICS.T1_DETECT_NEW_CLAIMS
  WAREHOUSE = DENIAL_WH
  SCHEDULE = '5 MINUTE'
  WHEN SYSTEM$STREAM_HAS_DATA('RAW.RAW_CLAIMS_STREAM')
AS
  INSERT INTO ANALYTICS.PIPELINE_LOG
  SELECT CURRENT_TIMESTAMP(), COUNT(*) FROM RAW.RAW_CLAIMS_STREAM;

-- Task 2: rebuild star schema + run all tests
CREATE OR REPLACE TASK ANALYTICS.T2_DBT_BUILD
  WAREHOUSE = DENIAL_WH
  AFTER ANALYTICS.T1_DETECT_NEW_CLAIMS
AS
  EXECUTE DBT PROJECT DENIAL_ANALYTICS_DB.DBT.DENIAL_DBT ARGS = 'build --target dev';

-- Task 3: rebuild the appeal queue from the fresh dbt tables
CREATE OR REPLACE TASK ANALYTICS.T3_REFRESH_APPEAL_QUEUE
  WAREHOUSE = DENIAL_WH
  AFTER ANALYTICS.T2_DBT_BUILD
AS
  CREATE OR REPLACE TABLE ANALYTICS.APPEAL_PRIORITY_QUEUE AS
  SELECT
    claim_id, claim_submission_date, payer_type, denial_reason_code, denial_category,
    recovery_action, claim_amount_usd, appeal_success_probability,
    CASE WHEN recovery_action IN ('recode_and_resubmit','verify_eligibility_resubmit')
         THEN 'Fast-track' ELSE 'Formal appeal' END AS work_tier,
    CASE WHEN recovery_action IN ('recode_and_resubmit','verify_eligibility_resubmit')
         THEN 25 ELSE 118 END AS est_work_cost_usd,
    ROUND(claim_amount_usd * appeal_success_probability, 2) AS expected_recovery_usd,
    ROUND(claim_amount_usd * appeal_success_probability - est_work_cost_usd, 2) AS net_value_usd,
    ROW_NUMBER() OVER (ORDER BY net_value_usd DESC) AS priority_rank
  FROM DBT.FACT_CLAIMS
  WHERE is_denied = 1 AND appealable = TRUE;

-- Turn the tasks on (children first, root last)
ALTER TASK ANALYTICS.T3_REFRESH_APPEAL_QUEUE RESUME;
ALTER TASK ANALYTICS.T2_DBT_BUILD RESUME;
ALTER TASK ANALYTICS.T1_DETECT_NEW_CLAIMS RESUME;

--Test
-- 1) Add one test claim (a copy of a pending claim with a new ID)
INSERT INTO RAW.RAW_CLAIMS
SELECT * REPLACE ('TEST-0001' AS claim_id)
FROM RAW.RAW_CLAIMS WHERE outcome = 'pending' LIMIT 1;

-- 2) The stream should now show 1 change
SELECT COUNT(*) FROM RAW.RAW_CLAIMS_STREAM;

-- 3) Run the pipeline now instead of waiting 5 minutes
EXECUTE TASK ANALYTICS.T1_DETECT_NEW_CLAIMS;

SELECT name, state, scheduled_time, error_message
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY())
ORDER BY scheduled_time DESC LIMIT 10;

SELECT COUNT(*) FROM DBT.FACT_CLAIMS;      -- should be 120001
SELECT * FROM ANALYTICS.PIPELINE_LOG;      -- 1 row, rows_changed = 1

DELETE FROM RAW.RAW_CLAIMS WHERE claim_id = 'TEST-0001';
EXECUTE TASK ANALYTICS.T1_DETECT_NEW_CLAIMS;   -- pipeline removes it again → back to 120000

-- after it finishes, pause the schedule
ALTER TASK ANALYTICS.T1_DETECT_NEW_CLAIMS SUSPEND;
USE ROLE ACCOUNTADMIN;
USE WAREHOUSE DENIAL_WH;
USE DATABASE DENIAL_ANALYTICS_DB;
USE SCHEMA RAW;

CREATE OR REPLACE FILE FORMAT CSV_LOAD_FF
  TYPE = CSV SKIP_HEADER = 1
  FIELD_OPTIONALLY_ENCLOSED_BY = '"'
  NULL_IF = ('') EMPTY_FIELD_AS_NULL = TRUE;

CREATE OR REPLACE TABLE RAW_CLAIMS (
  claim_id VARCHAR, claim_submission_date DATE, claim_year INT, claim_quarter VARCHAR,
  payer_type VARCHAR, provider_specialty VARCHAR, place_of_service_code VARCHAR,
  place_of_service_desc VARCHAR, cpt_code VARCHAR, modifier VARCHAR,
  primary_icd10_dx VARCHAR, primary_icd10_desc VARCHAR, secondary_icd10_dx VARCHAR,
  secondary_dx_count INT, prior_auth_required BOOLEAN, prior_auth_obtained BOOLEAN,
  prior_auth_number VARCHAR, documentation_completeness FLOAT, claim_amount_usd NUMBER(12,2),
  outcome VARCHAR, denial_reason_code VARCHAR, denial_category VARCHAR,
  dataset_version VARCHAR, synthetic_flag BOOLEAN, generation_date DATE);

CREATE OR REPLACE TABLE RAW_DENIAL_LABELS (
  claim_id VARCHAR, denial_category VARCHAR, denial_reason_code VARCHAR,
  denial_code_description VARCHAR, appealable BOOLEAN, appeal_success_probability FLOAT,
  recovery_action VARCHAR, estimated_recovery_usd NUMBER(12,2), dataset_version VARCHAR);

CREATE OR REPLACE TABLE RAW_PAYER_RULES (
  payer_type VARCHAR, cpt_code VARCHAR, requires_prior_auth BOOLEAN, auth_lead_time_days INT,
  historical_denial_rate FLOAT, avg_payment_turnaround_days INT,
  timely_filing_limit_days INT, dataset_version VARCHAR);

CREATE OR REPLACE TABLE RAW_TRAIN_TEST_SPLIT (
  claim_id VARCHAR, split VARCHAR, dataset_version VARCHAR);

COPY INTO RAW_CLAIMS
  FROM @CLAIMS_STAGE FILES = ('claims_main.csv')
  FILE_FORMAT = (FORMAT_NAME = 'CSV_LOAD_FF') FORCE = TRUE;

COPY INTO RAW_DENIAL_LABELS
  FROM @CLAIMS_STAGE FILES = ('denial_labels.csv')
  FILE_FORMAT = (FORMAT_NAME = 'CSV_LOAD_FF') FORCE = TRUE;

COPY INTO RAW_PAYER_RULES
  FROM @CLAIMS_STAGE FILES = ('payer_rules (1).csv')
  FILE_FORMAT = (FORMAT_NAME = 'CSV_LOAD_FF') FORCE = TRUE;

COPY INTO RAW_TRAIN_TEST_SPLIT
  FROM @CLAIMS_STAGE FILES = ('train_test_split.csv')
  FILE_FORMAT = (FORMAT_NAME = 'CSV_LOAD_FF') FORCE = TRUE;

SELECT 'claims' AS tbl, COUNT(*) AS row_count FROM RAW_CLAIMS UNION ALL
SELECT 'labels', COUNT(*) FROM RAW_DENIAL_LABELS UNION ALL
SELECT 'rules',  COUNT(*) FROM RAW_PAYER_RULES UNION ALL
SELECT 'split',  COUNT(*) FROM RAW_TRAIN_TEST_SPLIT;
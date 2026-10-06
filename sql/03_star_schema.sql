USE ROLE ACCOUNTADMIN;
USE WAREHOUSE DENIAL_WH;
USE DATABASE DENIAL_ANALYTICS_DB;
CREATE SCHEMA IF NOT EXISTS MODELED;
USE SCHEMA MODELED;

-- Lookup tables
CREATE OR REPLACE TABLE DIM_PAYER AS
SELECT DISTINCT payer_type FROM RAW.RAW_CLAIMS;

CREATE OR REPLACE TABLE DIM_SPECIALTY AS
SELECT DISTINCT provider_specialty FROM RAW.RAW_CLAIMS;

CREATE OR REPLACE TABLE DIM_PROCEDURE AS
SELECT DISTINCT cpt_code FROM RAW.RAW_CLAIMS;

CREATE OR REPLACE TABLE DIM_DIAGNOSIS AS
SELECT DISTINCT primary_icd10_dx AS icd10_code, primary_icd10_desc AS icd10_desc
FROM RAW.RAW_CLAIMS;

CREATE OR REPLACE TABLE DIM_DENIAL_REASON AS
SELECT DISTINCT denial_reason_code, denial_code_description
FROM RAW.RAW_DENIAL_LABELS;

-- Main table: one row per claim
CREATE OR REPLACE TABLE FACT_CLAIMS AS
SELECT
  c.claim_id,
  c.claim_submission_date,
  c.claim_year,
  c.claim_quarter,
  c.payer_type,
  c.provider_specialty,
  c.place_of_service_code,
  c.cpt_code,
  c.modifier,
  c.primary_icd10_dx AS icd10_code,
  c.secondary_dx_count,
  c.prior_auth_required,
  c.prior_auth_obtained,
  c.documentation_completeness,
  c.claim_amount_usd,
  c.outcome,
  CASE WHEN c.outcome = 'denied' THEN 1
       WHEN c.outcome IN ('paid','partial_pay') THEN 0 END AS is_denied,
  c.denial_reason_code,
  c.denial_category,
  l.appealable,
  l.appeal_success_probability,
  l.recovery_action,
  l.estimated_recovery_usd,
  s.split
FROM RAW.RAW_CLAIMS c
LEFT JOIN RAW.RAW_DENIAL_LABELS l    ON c.claim_id = l.claim_id
LEFT JOIN RAW.RAW_TRAIN_TEST_SPLIT s ON c.claim_id = s.claim_id;

-- Check
SELECT 'payers' AS tbl, COUNT(*) AS row_count FROM DIM_PAYER UNION ALL
SELECT 'specialties', COUNT(*) FROM DIM_SPECIALTY UNION ALL
SELECT 'procedures',  COUNT(*) FROM DIM_PROCEDURE UNION ALL
SELECT 'diagnoses',   COUNT(*) FROM DIM_DIAGNOSIS UNION ALL
SELECT 'denial reasons', COUNT(*) FROM DIM_DENIAL_REASON UNION ALL
SELECT 'claims',      COUNT(*) FROM FACT_CLAIMS;

USE SCHEMA DENIAL_ANALYTICS_DB.MODELED;

-- Each lookup table: mark its ID column as unique
ALTER TABLE DIM_PAYER         ADD PRIMARY KEY (payer_type);
ALTER TABLE DIM_SPECIALTY     ADD PRIMARY KEY (provider_specialty);
ALTER TABLE DIM_PROCEDURE     ADD PRIMARY KEY (cpt_code);
ALTER TABLE DIM_DIAGNOSIS     ADD PRIMARY KEY (icd10_code);
ALTER TABLE DIM_DENIAL_REASON ADD PRIMARY KEY (denial_reason_code);
ALTER TABLE FACT_CLAIMS       ADD PRIMARY KEY (claim_id);

-- Main table: link each column to its lookup table
ALTER TABLE FACT_CLAIMS ADD FOREIGN KEY (payer_type)         REFERENCES DIM_PAYER (payer_type);
ALTER TABLE FACT_CLAIMS ADD FOREIGN KEY (provider_specialty) REFERENCES DIM_SPECIALTY (provider_specialty);
ALTER TABLE FACT_CLAIMS ADD FOREIGN KEY (cpt_code)           REFERENCES DIM_PROCEDURE (cpt_code);
ALTER TABLE FACT_CLAIMS ADD FOREIGN KEY (icd10_code)         REFERENCES DIM_DIAGNOSIS (icd10_code);
ALTER TABLE FACT_CLAIMS ADD FOREIGN KEY (denial_reason_code) REFERENCES DIM_DENIAL_REASON (denial_reason_code);
# Claim Denial Risk & Appeal Prioritization
**Snowflake · dbt · Snowpark ML · Streamlit · Cortex Analyst**

Hospitals lose millions to denied insurance claims, and most billing teams work denials
oldest-first, so a $50 denial gets the same attention as a $30,000 one. This project builds
a system in Snowflake that:

1. **Predicts denial risk before a claim is sent**, so staff can fix risky claims first
2. **Ranks denied claims by expected dollars recovered**, so limited staff time goes where it pays most
3. **Answers plain-English questions** ("top 10 claims to appeal") with Cortex Analyst

---

## Key results

| Finding | Result |
|---|---|
| Claims analyzed | 120,000 (111,512 with a final outcome) |
| Denial rate | 30.2% · $74.1M denied |
| Biggest denial reasons | Medical necessity ($20.7M), coding errors ($16.3M), missing prior auth ($13.8M) |
| Missing prior authorization | 79% denied vs. 27% when not missing |
| **Top 1,000 claims worked by priority vs. oldest-first** | **$10.4M vs. $1.06M recovered (9.8×)** |

![Appeal queue](screenshots/appeal_queue.png)

---

## How it works

```
CSV files → RAW → staging (dbt views) → star schema (dbt tables) → risk model + appeal queue → app + AI chat
                      ▲                                                                         │
                      └──────────── stream + 3-task DAG re-runs the pipeline on new claims ─────┘
```

| Layer | What it does |
|---|---|
| **RAW** | 4 CSVs loaded as-is with explicit column types (protects codes like CPT `H0001` and POS `02`) |
| **dbt staging** | Light cleanup and an `is_denied` flag (1 = denied, 0 = paid/partial, null = pending) |
| **dbt marts** | Star schema: `fact_claims` + 5 dimensions (payer, specialty, procedure, diagnosis, denial reason) |
| **Data quality** | 22 dbt tests + 13 SQL checks (uniqueness, nulls, relationships, accepted values, ranges, reconciliation), all passing |
| **Risk model** | Logistic regression in a Snowflake Notebook, trained on a 70/15/15 split |
| **Appeal queue** | Net value = claim amount × appeal success probability − work cost |
| **App** | Streamlit in Snowflake: Overview, Risk check, and Appeal queue tabs |
| **AI layer** | Semantic view + Cortex Analyst for natural-language questions |
| **Automation** | Stream on raw claims → detect new rows → `dbt build` → refresh appeal queue |

![dbt lineage](screenshots/dbt_lineage.png)

---

## Model validation (ablation test)

The first model scored an AUC of 0.985, too good to be realistic. Removing one field
(documentation completeness) showed the synthetic data was built around it:

| Model | Test AUC | Precision in top 10% riskiest | Baseline denial rate |
|---|---|---|---|
| v1: all features | 0.985 | 100% | 30.5% |
| v2: without documentation score | 0.610 | 59.3% | 30.5% |

Without that field, the model still roughly **doubles the hit rate**: claims it flags as the
riskiest 10% are denied 59% of the time vs. 30.5% on average. Missing prior authorization is
the dominant driver.

**Leakage control:** post-denial fields (denial code, denial category) were excluded from training,
since they only exist after a claim is denied.

---

## Appeal prioritization logic

- **Expected recovery** = claim amount × appeal success probability
- **Work cost** = $25 for simple resubmissions (recode, eligibility) and $118 for formal appeals
  (medical necessity, missing auth), based on published industry rework-cost estimates
- **Net value** = expected recovery − work cost → rank highest first
- Duplicate and timely-filing denials are not appealable and are excluded

---

## Screenshots

**Overview**
![Overview](screenshots/overview.png)

**Risk check: claims to fix before sending**
![Risk check](screenshots/risk_check.png)

**AI chat: Cortex Analyst answering "top 10 claims to appeal"**
![AI chat](screenshots/ai_chat.png)

---

## Repository structure

```
├── README.md
├── 05_denial_risk_model.py   # risk model + ablation (Snowflake Notebook code)
├── streamlit_app.py          # Streamlit in Snowflake app
├── sql/                      # 01_setup → 09_automation, run in order
├── denial_dbt/               # dbt project: staging + marts models, tests
└── screenshots/
```

**SQL files:**
`01_setup` (warehouse, database, stage) · `02_load_data` (raw tables) · `03_star_schema` ·
`04_analysis` · `06_appeal_queue` · `07_semantic_view` (Cortex Analyst) · `08_data_quality` ·
`09_automation` (stream + tasks)

---

## Limits

- **Synthetic data.** Not real patient data. Its 30% denial rate is well above the roughly
  10–12% typically reported for real-world claims.
- **Model accuracy is data-dependent.** The v1 AUC reflects how the synthetic data was generated;
  real claims would score lower, closer to the v2 result.
- **Appeal success probabilities come from the dataset**, not observed real-world appeal outcomes.
- **Work costs are industry averages**, not a specific organization's costs.

---

## Tech stack
Snowflake (SQL, Snowpark, Notebooks, Streamlit in Snowflake, Semantic Views, Cortex Analyst,
Streams & Tasks) · dbt · Python (pandas, scikit-learn)

## Data source
[DenialIQ: 120K Medical Claims | X12 Denial Codes (Kaggle)](https://www.kaggle.com/datasets/nudratabbas/denialiq-120k-medical-claims-x12-denial-codes)
. The dataset is not included in this repo; download it from Kaggle.

---

**Author:** Swathishri Balachandar

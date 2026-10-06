import os
import streamlit as st

st.set_page_config(page_title="Denial IQ", layout="wide")
conn = st.connection("snowflake", ttl=os.getenv("SNOWFLAKE_CONNECTION_TTL"))
session = conn.session()

# ---------- Look & feel ----------
st.markdown("""
<style>
html, body, [class*="css"] { font-size: 18px; }
.block-container { padding-top: 2rem; max-width: 1400px; }
h1 { font-size: 2.6rem !important; }
h3 { font-size: 1.4rem !important; margin-top: 1rem; }
button[data-baseweb="tab"] p { font-size: 1.15rem; font-weight: 600; }
[data-testid="stMetric"] {
    background: #F4F7FB; border: 1px solid #DCE3EC;
    border-radius: 12px; padding: 18px 20px;
}
[data-testid="stMetricLabel"] p { font-size: 1rem; color: #4A5568; }
[data-testid="stMetricValue"] { font-size: 2.2rem; font-weight: 700; color: #1A3B6E; }
</style>
""", unsafe_allow_html=True)

FACT  = "DENIAL_ANALYTICS_DB.MODELED.FACT_CLAIMS"
SCORE = "DENIAL_ANALYTICS_DB.ANALYTICS.DENIAL_RISK_SCORES"
QUEUE = "DENIAL_ANALYTICS_DB.ANALYTICS.APPEAL_PRIORITY_QUEUE"

def q(sql):
    return session.sql(sql).to_pandas()

money = lambda label: st.column_config.NumberColumn(label, format="$%.0f")

st.title("Claim Denial Risk & Appeal Prioritization")
st.caption("Synthetic data: DenialIQ 120K claims (Kaggle) · Work cost assumptions: \\$25 per resubmission, \\$118 per formal appeal")

tab0, tab1, tab2 = st.tabs(["📊 Overview", "🛡️ Risk check (before sending)", "💰 Appeal queue (after denial)"])

# ---------------- OVERVIEW ----------------
with tab0:
    k = q(f"""
        SELECT COUNT(*) AS CLAIMS, AVG(is_denied) AS RATE,
               SUM(IFF(is_denied = 1, claim_amount_usd, 0)) AS DENIED_USD
        FROM {FACT} WHERE is_denied IS NOT NULL""")
    rec = q(f"SELECT SUM(net_value_usd) AS NET FROM {QUEUE}")

    c1, c2, c3, c4 = st.columns(4)
    c1.metric("Claims with an outcome", f"{int(k.CLAIMS[0]):,}")
    c2.metric("Denial rate", f"{float(k.RATE[0]):.1%}")
    c3.metric("Dollars denied", f"${float(k.DENIED_USD[0])/1e6:,.1f}M")
    c4.metric("Recoverable (net of work cost)", f"${float(rec.NET[0])/1e6:,.1f}M")

    left, right = st.columns(2)
    with left:
        st.subheader("Dollars denied by reason")
        by_cat = q(f"""
            SELECT INITCAP(REPLACE(denial_category, '_', ' ')) AS REASON,
                   ROUND(SUM(claim_amount_usd)) AS DOLLARS
            FROM {FACT} WHERE is_denied = 1
            GROUP BY 1 ORDER BY 2 DESC""")
        st.bar_chart(by_cat, x="REASON", y="DOLLARS", height=380)
    with right:
        st.subheader("Dollars denied by payer")
        by_payer = q(f"""
            SELECT REPLACE(payer_type, '_', ' ') AS PAYER,
                   ROUND(SUM(claim_amount_usd)) AS DOLLARS
            FROM {FACT} WHERE is_denied = 1
            GROUP BY 1 ORDER BY 2 DESC""")
        st.bar_chart(by_payer, x="PAYER", y="DOLLARS", height=380)

# ---------------- RISK CHECK ----------------
with tab1:
    cutoff = st.slider("Show pending claims with denial risk above", 0.0, 1.0, 0.5, 0.05)
    risk = q(f"""
        SELECT f.claim_id, REPLACE(f.payer_type, '_', ' ') AS payer,
               REPLACE(f.provider_specialty, '_', ' ') AS specialty, f.cpt_code,
               f.claim_amount_usd, r.denial_risk_score,
               CASE
                 WHEN f.prior_auth_required AND NOT COALESCE(f.prior_auth_obtained, FALSE)
                      THEN 'Prior auth missing'
                 WHEN f.documentation_completeness < 0.6 THEN 'Incomplete documentation'
                 WHEN f.documentation_completeness < 0.8 THEN 'Documentation borderline'
                 ELSE 'Other factors'
               END AS main_issue,
               f.documentation_completeness
        FROM {FACT} f JOIN {SCORE} r ON f.claim_id = r.claim_id
        WHERE f.outcome = 'pending' AND r.denial_risk_score >= {cutoff}
        ORDER BY r.denial_risk_score DESC""")

    c1, c2 = st.columns(2)
    c1.metric("High-risk pending claims", f"{len(risk):,}")
    c2.metric("Dollars at risk", f"${risk['CLAIM_AMOUNT_USD'].sum():,.0f}")

    st.subheader("What to fix first")
    st.bar_chart(risk.groupby("MAIN_ISSUE").size().rename("CLAIMS"), height=300)

    st.subheader("Claims to review before sending")
    st.dataframe(
        risk, use_container_width=True, hide_index=True, height=450,
        column_config={
            "CLAIM_ID": "Claim ID", "PAYER": "Payer", "SPECIALTY": "Specialty",
            "CPT_CODE": "CPT", "CLAIM_AMOUNT_USD": money("Claim amount"),
            "DENIAL_RISK_SCORE": st.column_config.ProgressColumn(
                "Denial risk", min_value=0, max_value=1, format="%.2f"),
            "MAIN_ISSUE": "Main issue",
            "DOCUMENTATION_COMPLETENESS": st.column_config.NumberColumn(
                "Documentation score", format="%.2f"),
        })
    st.download_button("⬇️ Download list (CSV)", risk.to_csv(index=False),
                       "high_risk_pending_claims.csv", "text/csv")

# ---------------- APPEAL QUEUE ----------------
with tab2:
    n = st.number_input("Claims your team can work", 100, 28000, 1000, 100)

    cmp = q(f"""
        WITH r AS (
          SELECT net_value_usd, priority_rank,
                 ROW_NUMBER() OVER (ORDER BY claim_submission_date, claim_id) AS fifo_rank
          FROM {QUEUE})
        SELECT SUM(IFF(priority_rank <= {n}, net_value_usd, 0)) AS PRIORITY,
               SUM(IFF(fifo_rank     <= {n}, net_value_usd, 0)) AS FIFO
        FROM r""")
    p, f = float(cmp.PRIORITY[0]), float(cmp.FIFO[0])

    c1, c2, c3 = st.columns(3)
    c1.metric("Recovered: priority order", f"${p:,.0f}")
    c2.metric("Recovered: oldest first", f"${f:,.0f}")
    c3.metric("Improvement", f"{p/f:.1f}×")

    st.subheader("Dollars recovered vs. claims worked")
    curve = q(f"""
        WITH r AS (
          SELECT net_value_usd, priority_rank,
                 ROW_NUMBER() OVER (ORDER BY claim_submission_date, claim_id) AS fifo_rank
          FROM {QUEUE}),
        p AS (SELECT priority_rank AS n,
                     SUM(net_value_usd) OVER (ORDER BY priority_rank) AS cum FROM r),
        f AS (SELECT fifo_rank AS n,
                     SUM(net_value_usd) OVER (ORDER BY fifo_rank) AS cum FROM r)
        SELECT p.n AS CLAIMS_WORKED, p.cum AS "Priority order", f.cum AS "Oldest first"
        FROM p JOIN f ON p.n = f.n
        WHERE MOD(p.n, 100) = 0
        ORDER BY 1""")
    st.line_chart(curve, x="CLAIMS_WORKED", y=["Priority order", "Oldest first"], height=380)

    st.subheader("Work queue")
    tier = st.selectbox("Work tier", ["All", "Fast-track", "Formal appeal"])
    where = "" if tier == "All" else f"WHERE work_tier = '{tier}'"
    queue = q(f"""
        SELECT priority_rank, claim_id, REPLACE(payer_type, '_', ' ') AS payer,
               INITCAP(REPLACE(denial_category, '_', ' ')) AS denial_reason, work_tier,
               claim_amount_usd, appeal_success_probability,
               expected_recovery_usd, est_work_cost_usd, net_value_usd
        FROM {QUEUE} {where}
        ORDER BY priority_rank
        LIMIT {n}""")
    st.dataframe(
        queue, use_container_width=True, hide_index=True, height=450,
        column_config={
            "PRIORITY_RANK": "Rank", "CLAIM_ID": "Claim ID", "PAYER": "Payer",
            "DENIAL_REASON": "Denial reason", "WORK_TIER": "Work tier",
            "CLAIM_AMOUNT_USD": money("Claim amount"),
            "APPEAL_SUCCESS_PROBABILITY": st.column_config.ProgressColumn(
                "Win chance", min_value=0, max_value=1, format="%.2f"),
            "EXPECTED_RECOVERY_USD": money("Expected recovery"),
            "EST_WORK_COST_USD": money("Work cost"),
            "NET_VALUE_USD": money("Net value"),
        })
    st.download_button("⬇️ Download queue (CSV)", queue.to_csv(index=False),
                       "appeal_priority_queue.csv", "text/csv")
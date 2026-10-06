from snowflake.snowpark.context import get_active_session
import pandas as pd, numpy as np
from sklearn.linear_model import LogisticRegression
from sklearn.metrics import roc_auc_score

session = get_active_session()
df = session.table("DENIAL_ANALYTICS_DB.MODELED.FACT_CLAIMS").to_pandas()
print(df.shape)

df["AUTH_MISSING"] = ((df["PRIOR_AUTH_REQUIRED"] == True) & (df["PRIOR_AUTH_OBTAINED"] != True)).astype(int)

cat = ["PAYER_TYPE", "PROVIDER_SPECIALTY", "PLACE_OF_SERVICE_CODE", "MODIFIER"]
X = pd.get_dummies(df[cat].fillna("none"), drop_first=True).astype(float)
X["AUTH_MISSING"] = df["AUTH_MISSING"]
X["DOC_COMPLETENESS"] = df["DOCUMENTATION_COMPLETENESS"].astype(float)
X["LOG_AMOUNT"] = np.log(df["CLAIM_AMOUNT_USD"].astype(float))
X["SECONDARY_DX_COUNT"] = df["SECONDARY_DX_COUNT"].astype(float)

labeled = df["IS_DENIED"].notna()
train = labeled & (df["SPLIT"] == "train")
test  = labeled & (df["SPLIT"] == "test")
print(X.shape, train.sum(), test.sum())

model = LogisticRegression(max_iter=2000)
model.fit(X[train], df.loc[train, "IS_DENIED"].astype(int))

auc = roc_auc_score(df.loc[test, "IS_DENIED"].astype(int), model.predict_proba(X[test])[:, 1])
print("Test AUC:", round(auc, 3))
print(pd.Series(model.coef_[0], X.columns).sort_values(ascending=False).head(8))

df["DENIAL_RISK_SCORE"] = model.predict_proba(X)[:, 1].round(4)

session.sql("CREATE SCHEMA IF NOT EXISTS DENIAL_ANALYTICS_DB.ANALYTICS").collect()
session.write_pandas(
    df[["CLAIM_ID", "OUTCOME", "DENIAL_RISK_SCORE", "SPLIT"]],
    "DENIAL_RISK_SCORES",
    database="DENIAL_ANALYTICS_DB", schema="ANALYTICS",
    auto_create_table=True, overwrite=True)
print("saved")


# comparing both models
def evaluate(features, name):
    m = LogisticRegression(max_iter=3000)
    m.fit(features[train], df.loc[train, "IS_DENIED"].astype(int))
    p = m.predict_proba(features[test])[:, 1]
    y_true = df.loc[test, "IS_DENIED"].astype(int).values
    top10 = np.argsort(-p)[: int(len(p) * 0.10)]
    return {"MODEL": name,
            "TEST_AUC": round(roc_auc_score(y_true, p), 3),
            "PRECISION_TOP_10PCT": round(y_true[top10].mean(), 3),
            "BASELINE_DENIAL_RATE": round(y_true.mean(), 3)}, m

X_v2 = X.drop(columns=["DOC_COMPLETENESS"])

r1, model_v1 = evaluate(X, "v1: all features")
r2, model_v2 = evaluate(X_v2, "v2: without documentation score")

comparison = pd.DataFrame([r1, r2])
print(comparison.to_string(index=False))
print()
print("v2 top drivers:")
print(pd.Series(model_v2.coef_[0], X_v2.columns).sort_values(ascending=False).head(6))

# saving the comparison
session.write_pandas(comparison, "MODEL_COMPARISON",
    database="DENIAL_ANALYTICS_DB", schema="ANALYTICS",
    auto_create_table=True, overwrite=True)
print("saved")
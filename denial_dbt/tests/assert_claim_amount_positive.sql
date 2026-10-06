select * from {{ ref('fact_claims') }}
where claim_amount_usd <= 0
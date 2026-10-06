select * from {{ ref('fact_claims') }}
where (outcome = 'denied') <> (denial_reason_code is not null)
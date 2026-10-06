select
    claim_id,
    claim_submission_date,
    claim_year,
    claim_quarter,
    payer_type,
    provider_specialty,
    place_of_service_code,
    cpt_code,
    modifier,
    primary_icd10_dx   as icd10_code,
    primary_icd10_desc as icd10_desc,
    secondary_dx_count,
    prior_auth_required,
    prior_auth_obtained,
    documentation_completeness,
    claim_amount_usd,
    outcome,
    case when outcome = 'denied' then 1
         when outcome in ('paid', 'partial_pay') then 0 end as is_denied,
    denial_reason_code,
    denial_category
from {{ source('raw', 'RAW_CLAIMS') }}
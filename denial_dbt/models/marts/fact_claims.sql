select
    c.claim_id,
    c.claim_submission_date,
    c.claim_year,
    c.claim_quarter,
    c.payer_type,
    c.provider_specialty,
    c.place_of_service_code,
    c.cpt_code,
    c.modifier,
    c.icd10_code,
    c.secondary_dx_count,
    c.prior_auth_required,
    c.prior_auth_obtained,
    c.documentation_completeness,
    c.claim_amount_usd,
    c.outcome,
    c.is_denied,
    c.denial_reason_code,
    c.denial_category,
    l.appealable,
    l.appeal_success_probability,
    l.recovery_action,
    l.estimated_recovery_usd,
    s.split
from {{ ref('stg_claims') }} c
left join {{ ref('stg_denial_labels') }} l on c.claim_id = l.claim_id
left join {{ ref('stg_train_test_split') }} s on c.claim_id = s.claim_id
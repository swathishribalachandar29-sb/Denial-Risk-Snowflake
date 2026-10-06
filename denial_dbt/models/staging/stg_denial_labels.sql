select
    claim_id,
    denial_reason_code,
    denial_code_description,
    appealable,
    appeal_success_probability,
    recovery_action,
    estimated_recovery_usd
from {{ source('raw', 'RAW_DENIAL_LABELS') }}
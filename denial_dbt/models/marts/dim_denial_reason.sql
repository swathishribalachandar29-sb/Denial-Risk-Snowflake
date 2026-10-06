select distinct denial_reason_code, denial_code_description
from {{ ref('stg_denial_labels') }}
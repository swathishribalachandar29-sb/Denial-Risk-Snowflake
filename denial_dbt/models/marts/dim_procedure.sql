select distinct cpt_code from {{ ref('stg_claims') }}

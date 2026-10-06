select claim_id, split
from {{ source('raw', 'RAW_TRAIN_TEST_SPLIT') }}
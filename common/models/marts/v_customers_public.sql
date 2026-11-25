{{
    config(
        materialized = "view",
    )
}}

-- Shared public, non-PII analytics view over `dim_customers` using explicit
-- column pruning. Demonstrates that views carry column descriptions safely
-- alongside project-wide `persist_docs.columns: true` without attaching
-- unsupported `data_governance_tags` onto the view itself.

SELECT
    customer_id,
    country_code,
    loyalty_tier,
    completed_order_count,
    updated_at
FROM {{ ref('dim_customers') }}

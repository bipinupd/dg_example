{{
    config(
        materialized = "view",
    )
}}

-- Public, non-PII analytics view over `dim_customers` using explicit column
-- pruning. Demonstrates that views carry column descriptions safely when
-- `persist_docs.columns: true` is enabled project-wide without attempting to
-- attach unsupported `data_governance_tags` to the view itself.

SELECT
    customer_id,
    country_code,
    loyalty_tier,
    completed_order_count,
    updated_at
FROM {{ ref('dim_customers') }}

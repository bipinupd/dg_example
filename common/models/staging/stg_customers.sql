{{
    config(
        materialized = "view",
    )
}}

-- Shared staging view over `raw_customers`: trims whitespace (preserving case)
-- and casts string fields safely. Views do not attach `data_governance_tags`
-- directly; BigQuery enforces tags from the underlying `raw_customers` table.

SELECT
    SAFE_CAST(customer_id AS INT64) AS customer_id,
    NULLIF(TRIM(full_name), '') AS full_name,
    NULLIF(TRIM(email), '') AS email,
    NULLIF(TRIM(work_email), '') AS work_email,
    NULLIF(TRIM(ssn), '') AS ssn,
    NULLIF(TRIM(country_code), '') AS country_code,
    NULLIF(TRIM(loyalty_tier), '') AS loyalty_tier,
    SAFE_CAST(NULLIF(TRIM(annual_income_usd), '') AS NUMERIC) AS annual_income_usd,
    SAFE_CAST(NULLIF(TRIM(updated_at), '') AS TIMESTAMP) AS updated_at
FROM {{ ref('raw_customers') }}
WHERE customer_id IS NOT NULL

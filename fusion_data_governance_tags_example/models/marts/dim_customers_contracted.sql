{{
    config(
        materialized = "table",
    )
}}

-- Contract-enforced model (`contract: {enforced: true}` in schema.yml)
-- combining strict BigQuery schema type enforcement with top-level
-- `data_governance_tags` persisted via dbt v2 / Fusion batched ALTER TABLE DDL.

SELECT
    CAST(customer_id AS INT64) AS customer_id,
    CAST(email AS STRING) AS email,
    CAST(ssn AS STRING) AS ssn,
    CAST(loyalty_tier AS STRING) AS loyalty_tier,
    CAST(country_code AS STRING) AS country_code
FROM {{ ref('stg_customers') }}



-- Contract-enforced model (`contract: {enforced: true}` in schema.yml)
-- combining strict BigQuery schema type enforcement with top-level and nested
-- STRUCT leaf `data_governance_tags`.

SELECT
    CAST(customer_id AS INT64) AS customer_id,
    CAST(email AS STRING) AS email,
    CAST(loyalty_tier AS STRING) AS loyalty_tier,
    STRUCT(
        CAST(ssn AS STRING) AS ssn,
        CAST(country_code AS STRING) AS country_code
    ) AS identity
FROM `bipin-dev-project-465919`.`dbt_dgt_example`.`stg_customers`




-- SCD Type 2 snapshot over `dim_customers` demonstrating `data_governance_tags`
-- persisted on snapshot table columns (configured in snapshots/schema.yml).

SELECT
    customer_id,
    email,
    ssn,
    loyalty_tier,
    updated_at
FROM `bipin-dev-project-465919`.`dbt_dgt_example`.`dim_customers`

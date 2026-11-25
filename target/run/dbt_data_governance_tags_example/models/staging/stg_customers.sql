

  create or replace view `bipin-dev-project-465919`.`dbt_dgt_example`.`stg_customers`
  OPTIONS(
      description="""Cleaned staging view over `raw_customers`. BigQuery does not permit attaching `data_governance_tags` directly onto VIEW columns; column descriptions are persisted safely while access control and masking are inherited automatically from the tagged `raw_customers` table."""
    )
  as 

-- Staging view over `raw_customers`: trims whitespace (preserving case) and
-- casts string fields safely. Views do not attach `data_governance_tags`
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
FROM `bipin-dev-project-465919`.`dbt_dgt_example`.`raw_customers`
WHERE customer_id IS NOT NULL;


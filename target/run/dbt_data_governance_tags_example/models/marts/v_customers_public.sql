

  create or replace view `bipin-dev-project-465919`.`dbt_dgt_example`.`v_customers_public`
  OPTIONS(
      description="""Public non-PII analytics view over `dim_customers`. Carries column descriptions only (no direct `data_governance_tags`, since BigQuery only permits governance tags on tables)."""
    )
  as 

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
FROM `bipin-dev-project-465919`.`dbt_dgt_example`.`dim_customers`;


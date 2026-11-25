
  
    

    create or replace table `bipin-dev-project-465919`.`dbt_dgt_example`.`dim_customers`
      
    
    

    
    OPTIONS(
      description="""Core customer dimension table demonstrating top-level scalar column `data_governance_tags` across both classification (`dbt_dgt_e2e_class`) and domain (`dbt_dgt_e2e_domain`) Tag Keys."""
    )
    as (
      

-- Core customer dimension table demonstrating top-level scalar column
-- `data_governance_tags` across two tag keys (classification + domain).
-- Applies early predicate pushdown (`status = 'completed'`) and early
-- aggregation (`GROUP BY customer_id`) before joining to `stg_customers`.

WITH completed_order_metrics AS (
    SELECT
        customer_id,
        COUNT(1) AS completed_order_count,
        COALESCE(SUM(amount_usd), CAST(0 AS NUMERIC)) AS lifetime_spend_usd
    FROM `bipin-dev-project-465919`.`dbt_dgt_example`.`stg_orders`
    WHERE status = 'completed'
    GROUP BY customer_id
)

SELECT
    c.customer_id,
    c.full_name,
    c.email,
    c.ssn,
    c.country_code,
    c.loyalty_tier,
    c.annual_income_usd,
    COALESCE(m.completed_order_count, 0) AS completed_order_count,
    COALESCE(m.lifetime_spend_usd, CAST(0 AS NUMERIC)) AS lifetime_spend_usd,
    c.updated_at
FROM `bipin-dev-project-465919`.`dbt_dgt_example`.`stg_customers` AS c
LEFT JOIN completed_order_metrics AS m
    ON c.customer_id = m.customer_id
    );
  
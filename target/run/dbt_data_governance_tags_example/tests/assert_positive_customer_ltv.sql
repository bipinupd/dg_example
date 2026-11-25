
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  -- Singular data test ensuring customer lifetime spend and completed order
-- counts are never negative in `dim_customers`.

SELECT
    customer_id,
    completed_order_count,
    lifetime_spend_usd
FROM `bipin-dev-project-465919`.`dbt_dgt_example`.`dim_customers`
WHERE completed_order_count < 0
   OR lifetime_spend_usd < 0
  
  
      
    ) dbt_internal_test

    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select lifetime_spend_usd
from `bipin-dev-project-465919`.`dbt_dgt_example`.`dim_customers`
where lifetime_spend_usd is null



  
  
      
    ) dbt_internal_test

    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select updated_at
from `bipin-dev-project-465919`.`dbt_dgt_example`.`dim_customers`
where updated_at is null



  
  
      
    ) dbt_internal_test
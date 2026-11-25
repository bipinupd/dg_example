
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select completed_order_count
from `bipin-dev-project-465919`.`dbt_dgt_example`.`dim_customers`
where completed_order_count is null



  
  
      
    ) dbt_internal_test
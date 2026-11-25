
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    



select customer_id
from `bipin-dev-project-465919`.`dbt_dgt_example`.`fct_customer_profiles`
where customer_id is null



  
  
      
    ) dbt_internal_test
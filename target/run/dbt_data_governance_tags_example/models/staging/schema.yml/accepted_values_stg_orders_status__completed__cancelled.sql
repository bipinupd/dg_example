
    
    select
      count(*) as failures,
      count(*) != 0 as should_warn,
      count(*) != 0 as should_error
    from (
      
    
  
    
    

with all_values as (

    select
        status as value_field,
        count(*) as n_records

    from `bipin-dev-project-465919`.`dbt_dgt_example`.`stg_orders`
    group by status

)

select *
from all_values
where value_field not in (
    'completed','cancelled'
)



  
  
      
    ) dbt_internal_test
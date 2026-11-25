
    
    

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




    
    

with all_values as (

    select
        loyalty_tier as value_field,
        count(*) as n_records

    from `bipin-dev-project-465919`.`dbt_dgt_example`.`stg_customers`
    group by loyalty_tier

)

select *
from all_values
where value_field not in (
    'Bronze','Silver','Gold','Platinum'
)



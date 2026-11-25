
      
  
    

    create table `bipin-dev-project-465919`.`dbt_dgt_example`.`customers_snapshot`
      
    
    

    
    OPTIONS(
      description="""SCD Type 2 history table for customer PII and loyalty tier. Demonstrates that `dbt snapshot` persists `data_governance_tags` onto snapshot tables when `persist_docs.columns: true` is enabled."""
    )
    as (
      
    

    select *,
        to_hex(md5(concat(coalesce(cast(customer_id as string), ''), '|',coalesce(cast(updated_at as string), '')))) as dbt_scd_id,
        updated_at as dbt_updated_at,
        updated_at as dbt_valid_from,
        
  
  coalesce(nullif(updated_at, updated_at), null)
  as dbt_valid_to
from (
        



-- SCD Type 2 snapshot over `dim_customers` demonstrating `data_governance_tags`
-- persisted on snapshot table columns (configured in snapshots/schema.yml).

SELECT
    customer_id,
    email,
    ssn,
    loyalty_tier,
    updated_at
FROM `bipin-dev-project-465919`.`dbt_dgt_example`.`dim_customers`

    ) sbq



    );
  
  
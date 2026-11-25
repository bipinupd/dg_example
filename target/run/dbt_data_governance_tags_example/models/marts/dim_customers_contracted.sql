
  
    

    create or replace table `bipin-dev-project-465919`.`dbt_dgt_example`.`dim_customers_contracted`
        
  (
    customer_id int64,
    email string,
    loyalty_tier string,
    identity struct<ssn string, country_code string>
    
    )

      
    
    

    
    OPTIONS(
      description="""Contract-enforced customer table combining `contract: {enforced: true}` type guarantees with top-level and nested STRUCT leaf Data Governance Tags."""
    )
    as (
      
    select customer_id, email, loyalty_tier, IF(identity IS NULL, NULL, STRUCT(identity.ssn AS ssn, identity.country_code AS country_code)) AS identity
    from (
        

-- Contract-enforced model (`contract: {enforced: true}` in schema.yml)
-- combining strict BigQuery schema type enforcement with top-level and nested
-- STRUCT leaf `data_governance_tags`.

SELECT
    CAST(customer_id AS INT64) AS customer_id,
    CAST(email AS STRING) AS email,
    CAST(loyalty_tier AS STRING) AS loyalty_tier,
    STRUCT(
        CAST(ssn AS STRING) AS ssn,
        CAST(country_code AS STRING) AS country_code
    ) AS identity
FROM `bipin-dev-project-465919`.`dbt_dgt_example`.`stg_customers`
    ) as model_subq
    );
  
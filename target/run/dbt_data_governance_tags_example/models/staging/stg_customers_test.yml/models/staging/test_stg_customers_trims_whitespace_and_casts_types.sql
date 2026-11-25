
    -- Build actual result given inputs
with dbt_internal_unit_test_actual as (
  select
    `customer_id`,`full_name`,`email`,`work_email`,`ssn`,`country_code`,`loyalty_tier`,`annual_income_usd`,`updated_at`, '''actual''' as `actual_or_expected`
  from (
    

with __dbt__cte__raw_customers as (

-- Fixture for raw_customers
select safe_cast(1 as INT64) as `customer_id`, safe_cast('''  Alice Mercer  ''' as STRING) as `full_name`, safe_cast('''  alice@example.com ''' as STRING) as `email`, safe_cast('''alice.w@corp.example.com''' as STRING) as `work_email`, safe_cast('''000-00-0001''' as STRING) as `ssn`, safe_cast(''' US ''' as STRING) as `country_code`, safe_cast(''' Gold ''' as STRING) as `loyalty_tier`, safe_cast('''145000.00''' as STRING) as `annual_income_usd`, safe_cast('''2026-01-10T09:15:00Z''' as STRING) as `updated_at`
union all
select safe_cast(null as INT64) as `customer_id`, safe_cast('''Invalid Row''' as STRING) as `full_name`, safe_cast('''invalid@example.com''' as STRING) as `email`, safe_cast('''invalid@example.com''' as STRING) as `work_email`, safe_cast('''000-00-0000''' as STRING) as `ssn`, safe_cast('''US''' as STRING) as `country_code`, safe_cast('''Bronze''' as STRING) as `loyalty_tier`, safe_cast('''0''' as STRING) as `annual_income_usd`, safe_cast('''2026-01-10T09:15:00Z''' as STRING) as `updated_at`
) -- Staging view over `raw_customers`: trims whitespace (preserving case) and
-- casts string fields safely. Views do not attach `data_governance_tags`
-- directly; BigQuery enforces tags from the underlying `raw_customers` table.

SELECT
    SAFE_CAST(customer_id AS INT64) AS customer_id,
    NULLIF(TRIM(full_name), '') AS full_name,
    NULLIF(TRIM(email), '') AS email,
    NULLIF(TRIM(work_email), '') AS work_email,
    NULLIF(TRIM(ssn), '') AS ssn,
    NULLIF(TRIM(country_code), '') AS country_code,
    NULLIF(TRIM(loyalty_tier), '') AS loyalty_tier,
    SAFE_CAST(NULLIF(TRIM(annual_income_usd), '') AS NUMERIC) AS annual_income_usd,
    SAFE_CAST(NULLIF(TRIM(updated_at), '') AS TIMESTAMP) AS updated_at
FROM __dbt__cte__raw_customers
WHERE customer_id IS NOT NULL
  ) _dbt_internal_unit_test_actual
),
-- Build expected result
dbt_internal_unit_test_expected as (
  select
    `customer_id`, `full_name`, `email`, `work_email`, `ssn`, `country_code`, `loyalty_tier`, `annual_income_usd`, `updated_at`, '''expected''' as `actual_or_expected`
  from (
    select safe_cast(1 as INT64) as `customer_id`, safe_cast('''Alice Mercer''' as STRING) as `full_name`, safe_cast('''alice@example.com''' as STRING) as `email`, safe_cast('''alice.w@corp.example.com''' as STRING) as `work_email`, safe_cast('''000-00-0001''' as STRING) as `ssn`, safe_cast('''US''' as STRING) as `country_code`, safe_cast('''Gold''' as STRING) as `loyalty_tier`, safe_cast(145000 as NUMERIC) as `annual_income_usd`, safe_cast('''2026-01-10 09:15:00+00:00''' as TIMESTAMP) as `updated_at`
  ) _dbt_internal_unit_test_expected
)
-- Union actual and expected results
select * from dbt_internal_unit_test_actual
union all
select * from dbt_internal_unit_test_expected
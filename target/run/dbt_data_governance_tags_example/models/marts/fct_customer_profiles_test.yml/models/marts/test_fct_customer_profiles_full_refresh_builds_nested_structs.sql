
    -- Build actual result given inputs
with dbt_internal_unit_test_actual as (
  select
    `customer_id`,`primary_email`,`public_display_note`,`profile`,`order_events`,`updated_at`, '''actual''' as `actual_or_expected`
  from (
    

-- Incremental customer profile model demonstrating:
--   1. Production best practice for sensitive tables: incremental merges update
--      tables in place without a drop-and-recreate untagged window.
--   2. Nested STRUCT (`profile.work_email`), 2-level nested STRUCT
--      (`profile.identity.ssn`), and repeated ARRAY<STRUCT> leaf tags
--      (`order_events.actor_email`) supported by dbt-bigquery's REST patch.
--   3. Explicit tag clearing via `data_governance_tags: {}` (`public_display_note`).

WITH  __dbt__cte__stg_orders as (

-- Fixture for stg_orders
select safe_cast(1001 as INT64) as `order_id`, safe_cast(1 as INT64) as `customer_id`, safe_cast('''2026-01-11''' as DATE) as `order_date`, safe_cast(250 as NUMERIC) as `amount_usd`, safe_cast('''completed''' as STRING) as `status`, safe_cast('''actor.a@example.com''' as STRING) as `actor_email`, safe_cast('''checkout''' as STRING) as `event_type`
),  __dbt__cte__stg_customers as (

-- Fixture for stg_customers
select safe_cast(1 as INT64) as `customer_id`, safe_cast('''Alice Mercer''' as STRING) as `full_name`, safe_cast('''alice@example.com''' as STRING) as `email`, safe_cast('''alice.w@corp.example.com''' as STRING) as `work_email`, safe_cast('''000-00-0001''' as STRING) as `ssn`, safe_cast('''US''' as STRING) as `country_code`, safe_cast('''Gold''' as STRING) as `loyalty_tier`, safe_cast(145000 as NUMERIC) as `annual_income_usd`, safe_cast('''2026-01-10 09:15:00+00:00''' as TIMESTAMP) as `updated_at`
), customer_order_events AS (
    SELECT
        customer_id,
        ARRAY_AGG(
            STRUCT(
                order_id,
                order_date,
                actor_email,
                event_type
            )
            ORDER BY order_date, order_id
        ) AS order_events
    FROM __dbt__cte__stg_orders
    GROUP BY customer_id
),

filtered_customers AS (
    SELECT
        customer_id,
        email,
        work_email,
        ssn,
        country_code,
        loyalty_tier,
        updated_at
    FROM __dbt__cte__stg_customers
    
)

SELECT
    c.customer_id,
    c.email AS primary_email,
    CONCAT('Tier: ', COALESCE(c.loyalty_tier, 'Unknown')) AS public_display_note,
    STRUCT(
        c.work_email AS work_email,
        STRUCT(
            c.ssn AS ssn,
            c.country_code AS country_code
        ) AS identity
    ) AS profile,
    COALESCE(
        e.order_events,
        CAST([] AS ARRAY<STRUCT<order_id INT64, order_date DATE, actor_email STRING, event_type STRING>>)
    ) AS order_events,
    c.updated_at
FROM filtered_customers AS c
LEFT JOIN customer_order_events AS e
    ON c.customer_id = e.customer_id
  ) _dbt_internal_unit_test_actual
),
-- Build expected result
dbt_internal_unit_test_expected as (
  select
    `customer_id`, `primary_email`, `public_display_note`, `profile`, `order_events`, `updated_at`, '''expected''' as `actual_or_expected`
  from (
    SELECT
  1 AS customer_id,
  'alice@example.com' AS primary_email,
  'Tier: Gold' AS public_display_note,
  STRUCT(
    'alice.w@corp.example.com' AS work_email,
    STRUCT('000-00-0001' AS ssn, 'US' AS country_code) AS identity
  ) AS profile,
  [
    STRUCT(
      1001 AS order_id,
      DATE '2026-01-11' AS order_date,
      'actor.a@example.com' AS actor_email,
      'checkout' AS event_type
    )
  ] AS order_events,
  TIMESTAMP '2026-01-10 09:15:00+00:00' AS updated_at
  ) _dbt_internal_unit_test_expected
)
-- Union actual and expected results
select * from dbt_internal_unit_test_actual
union all
select * from dbt_internal_unit_test_expected
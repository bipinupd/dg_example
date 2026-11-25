

with __dbt__cte__raw_orders as (

-- Fixture for raw_orders
select safe_cast(1001 as INT64) as `order_id`, safe_cast(1 as INT64) as `customer_id`, safe_cast('''2026-01-11''' as STRING) as `order_date`, safe_cast('''250.00''' as STRING) as `amount_usd`, safe_cast('''completed''' as STRING) as `status`, safe_cast('''actor.a@example.com''' as STRING) as `actor_email`, safe_cast('''checkout''' as STRING) as `event_type`
union all
select safe_cast(1002 as INT64) as `order_id`, safe_cast(1 as INT64) as `customer_id`, safe_cast('''01/14/2026''' as STRING) as `order_date`, safe_cast('''125.50''' as STRING) as `amount_usd`, safe_cast('''cancelled''' as STRING) as `status`, safe_cast('''actor.a@example.com''' as STRING) as `actor_email`, safe_cast('''refund''' as STRING) as `event_type`
) -- Staging view over `raw_orders`: normalizes mixed date formats via COALESCE
-- + SAFE.PARSE_DATE, trims strings (preserving case), and casts numeric fields.

SELECT
    SAFE_CAST(order_id AS INT64) AS order_id,
    SAFE_CAST(customer_id AS INT64) AS customer_id,
    COALESCE(
        SAFE.PARSE_DATE('%Y-%m-%d', TRIM(order_date)),
        SAFE.PARSE_DATE('%m/%d/%Y', TRIM(order_date))
    ) AS order_date,
    SAFE_CAST(NULLIF(TRIM(amount_usd), '') AS NUMERIC) AS amount_usd,
    NULLIF(TRIM(status), '') AS status,
    NULLIF(TRIM(actor_email), '') AS actor_email,
    NULLIF(TRIM(event_type), '') AS event_type
FROM __dbt__cte__raw_orders
WHERE order_id IS NOT NULL
  AND customer_id IS NOT NULL
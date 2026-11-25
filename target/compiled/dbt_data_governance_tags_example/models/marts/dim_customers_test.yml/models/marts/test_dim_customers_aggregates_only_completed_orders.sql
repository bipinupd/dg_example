

-- Core customer dimension table demonstrating top-level scalar column
-- `data_governance_tags` across two tag keys (classification + domain).
-- Applies early predicate pushdown (`status = 'completed'`) and early
-- aggregation (`GROUP BY customer_id`) before joining to `stg_customers`.

WITH  __dbt__cte__stg_orders as (

-- Fixture for stg_orders
select safe_cast(1001 as INT64) as `order_id`, safe_cast(1 as INT64) as `customer_id`, safe_cast('''2026-01-11''' as DATE) as `order_date`, safe_cast(250 as NUMERIC) as `amount_usd`, safe_cast('''completed''' as STRING) as `status`, safe_cast('''actor.a@example.com''' as STRING) as `actor_email`, safe_cast('''checkout''' as STRING) as `event_type`
union all
select safe_cast(1002 as INT64) as `order_id`, safe_cast(1 as INT64) as `customer_id`, safe_cast('''2026-01-14''' as DATE) as `order_date`, safe_cast(125.5 as NUMERIC) as `amount_usd`, safe_cast('''completed''' as STRING) as `status`, safe_cast('''actor.a@example.com''' as STRING) as `actor_email`, safe_cast('''renewal''' as STRING) as `event_type`
union all
select safe_cast(1004 as INT64) as `order_id`, safe_cast(2 as INT64) as `customer_id`, safe_cast('''2026-01-16''' as DATE) as `order_date`, safe_cast(45 as NUMERIC) as `amount_usd`, safe_cast('''cancelled''' as STRING) as `status`, safe_cast('''actor.b@example.com''' as STRING) as `actor_email`, safe_cast('''refund''' as STRING) as `event_type`
),  __dbt__cte__stg_customers as (

-- Fixture for stg_customers
select safe_cast(1 as INT64) as `customer_id`, safe_cast('''Alice Mercer''' as STRING) as `full_name`, safe_cast('''alice@example.com''' as STRING) as `email`, safe_cast('''alice.w@corp.example.com''' as STRING) as `work_email`, safe_cast('''000-00-0001''' as STRING) as `ssn`, safe_cast('''US''' as STRING) as `country_code`, safe_cast('''Gold''' as STRING) as `loyalty_tier`, safe_cast(145000 as NUMERIC) as `annual_income_usd`, safe_cast('''2026-01-10 09:15:00+00:00''' as TIMESTAMP) as `updated_at`
union all
select safe_cast(2 as INT64) as `customer_id`, safe_cast('''Bob Chen''' as STRING) as `full_name`, safe_cast('''bob@example.com''' as STRING) as `email`, safe_cast('''bob.w@corp.example.com''' as STRING) as `work_email`, safe_cast('''000-00-0002''' as STRING) as `ssn`, safe_cast('''US''' as STRING) as `country_code`, safe_cast('''Silver''' as STRING) as `loyalty_tier`, safe_cast(98500.5 as NUMERIC) as `annual_income_usd`, safe_cast('''2026-01-12 14:30:00+00:00''' as TIMESTAMP) as `updated_at`
), completed_order_metrics AS (
    SELECT
        customer_id,
        COUNT(1) AS completed_order_count,
        COALESCE(SUM(amount_usd), CAST(0 AS NUMERIC)) AS lifetime_spend_usd
    FROM __dbt__cte__stg_orders
    WHERE status = 'completed'
    GROUP BY customer_id
)

SELECT
    c.customer_id,
    c.full_name,
    c.email,
    c.ssn,
    c.country_code,
    c.loyalty_tier,
    c.annual_income_usd,
    COALESCE(m.completed_order_count, 0) AS completed_order_count,
    COALESCE(m.lifetime_spend_usd, CAST(0 AS NUMERIC)) AS lifetime_spend_usd,
    c.updated_at
FROM __dbt__cte__stg_customers AS c
LEFT JOIN completed_order_metrics AS m
    ON c.customer_id = m.customer_id
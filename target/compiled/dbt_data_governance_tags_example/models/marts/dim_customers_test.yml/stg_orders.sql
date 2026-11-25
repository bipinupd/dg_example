
-- Fixture for stg_orders
select safe_cast(1001 as INT64) as `order_id`, safe_cast(1 as INT64) as `customer_id`, safe_cast('''2026-01-11''' as DATE) as `order_date`, safe_cast(250 as NUMERIC) as `amount_usd`, safe_cast('''completed''' as STRING) as `status`, safe_cast('''actor.a@example.com''' as STRING) as `actor_email`, safe_cast('''checkout''' as STRING) as `event_type`
union all
select safe_cast(1002 as INT64) as `order_id`, safe_cast(1 as INT64) as `customer_id`, safe_cast('''2026-01-14''' as DATE) as `order_date`, safe_cast(125.5 as NUMERIC) as `amount_usd`, safe_cast('''completed''' as STRING) as `status`, safe_cast('''actor.a@example.com''' as STRING) as `actor_email`, safe_cast('''renewal''' as STRING) as `event_type`
union all
select safe_cast(1004 as INT64) as `order_id`, safe_cast(2 as INT64) as `customer_id`, safe_cast('''2026-01-16''' as DATE) as `order_date`, safe_cast(45 as NUMERIC) as `amount_usd`, safe_cast('''cancelled''' as STRING) as `status`, safe_cast('''actor.b@example.com''' as STRING) as `actor_email`, safe_cast('''refund''' as STRING) as `event_type`
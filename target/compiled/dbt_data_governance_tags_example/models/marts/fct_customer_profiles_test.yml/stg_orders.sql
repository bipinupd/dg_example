
-- Fixture for stg_orders
select safe_cast(1001 as INT64) as `order_id`, safe_cast(1 as INT64) as `customer_id`, safe_cast('''2026-01-11''' as DATE) as `order_date`, safe_cast(250 as NUMERIC) as `amount_usd`, safe_cast('''completed''' as STRING) as `status`, safe_cast('''actor.a@example.com''' as STRING) as `actor_email`, safe_cast('''checkout''' as STRING) as `event_type`

-- Fixture for raw_orders
select safe_cast(1001 as INT64) as `order_id`, safe_cast(1 as INT64) as `customer_id`, safe_cast('''2026-01-11''' as STRING) as `order_date`, safe_cast('''250.00''' as STRING) as `amount_usd`, safe_cast('''completed''' as STRING) as `status`, safe_cast('''actor.a@example.com''' as STRING) as `actor_email`, safe_cast('''checkout''' as STRING) as `event_type`
union all
select safe_cast(1002 as INT64) as `order_id`, safe_cast(1 as INT64) as `customer_id`, safe_cast('''01/14/2026''' as STRING) as `order_date`, safe_cast('''125.50''' as STRING) as `amount_usd`, safe_cast('''cancelled''' as STRING) as `status`, safe_cast('''actor.a@example.com''' as STRING) as `actor_email`, safe_cast('''refund''' as STRING) as `event_type`
{% snapshot customers_snapshot %}

{{
    config(
        target_schema = target.schema,
        unique_key = "customer_id",
        strategy = "timestamp",
        updated_at = "updated_at",
        persist_docs = {"relation": true, "columns": true},
    )
}}

-- SCD Type 2 snapshot over `dim_customers` demonstrating `data_governance_tags`
-- persisted on snapshot table columns (configured in snapshots/schema.yml).

SELECT
    customer_id,
    email,
    ssn,
    loyalty_tier,
    updated_at
FROM {{ ref('dim_customers') }}

{% endsnapshot %}

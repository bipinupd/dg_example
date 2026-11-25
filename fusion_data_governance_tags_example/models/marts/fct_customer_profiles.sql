{{
    config(
        materialized = "incremental",
        unique_key = "customer_id",
        incremental_strategy = "merge",
        on_schema_change = "sync_all_columns",
    )
}}

-- Incremental customer profile table designed specifically for dbt v2 / Fusion:
--   1. Incremental merge avoids drop-and-recreate untagged exposure windows.
--   2. Sensitive fields (`primary_email`, `work_email`, `ssn`, `latest_actor_email`)
--      are modeled as TOP-LEVEL columns because BigQuery's `ALTER COLUMN` DDL
--      (used by dbt v2 / Fusion) does not accept dotted nested STRUCT paths.
--   3. Non-PII metadata lives inside `profile_metadata` (a STRUCT column with a
--      description only — proving Fusion's `record_names` detection permits
--      STRUCT descriptions while rejecting tags on STRUCT parents/dotted paths).
--   4. `public_display_note` uses `data_governance_tags: {}` to demonstrate
--      Fusion's explicit tag clearing (`data_governance_tags=[]`).

WITH latest_order_actor AS (
    SELECT
        customer_id,
        COUNT(1) AS total_event_count,
        ARRAY_AGG(actor_email ORDER BY order_date DESC, order_id DESC LIMIT 1)[SAFE_OFFSET(0)] AS latest_actor_email
    FROM {{ ref('stg_orders') }}
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
    FROM {{ ref('stg_customers') }}
    {% if is_incremental() %}
    WHERE updated_at >= (
        SELECT COALESCE(MAX(existing.updated_at), TIMESTAMP('1970-01-01 00:00:00 UTC'))
        FROM {{ this }} AS existing
    )
    {% endif %}
)

SELECT
    c.customer_id,
    c.email AS primary_email,
    c.work_email,
    c.ssn,
    o.latest_actor_email,
    CONCAT('Tier: ', COALESCE(c.loyalty_tier, 'Unknown')) AS public_display_note,
    STRUCT(
        c.country_code AS country_code,
        c.loyalty_tier AS loyalty_tier,
        COALESCE(o.total_event_count, 0) AS total_event_count
    ) AS profile_metadata,
    c.updated_at
FROM filtered_customers AS c
LEFT JOIN latest_order_actor AS o
    ON c.customer_id = o.customer_id

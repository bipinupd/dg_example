{{
    config(
        materialized = "incremental",
        unique_key = "customer_id",
        incremental_strategy = "merge",
        on_schema_change = "sync_all_columns",
    )
}}

-- Incremental customer profile model demonstrating:
--   1. Production best practice for sensitive tables: incremental merges update
--      tables in place without a drop-and-recreate untagged window.
--   2. Nested STRUCT (`profile.work_email`), 2-level nested STRUCT
--      (`profile.identity.ssn`), and repeated ARRAY<STRUCT> leaf tags
--      (`order_events.actor_email`) supported by dbt-bigquery's REST patch.
--   3. Explicit tag clearing via `data_governance_tags: {}` (`public_display_note`).

WITH customer_order_events AS (
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

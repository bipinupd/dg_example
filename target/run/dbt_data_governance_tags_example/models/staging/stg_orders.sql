

  create or replace view `bipin-dev-project-465919`.`dbt_dgt_example`.`stg_orders`
  OPTIONS(
      description="""Cleaned staging view over `raw_orders` with normalized DATE values and typed NUMERIC amounts. View columns carry descriptions only (no direct `data_governance_tags`)."""
    )
  as 

-- Staging view over `raw_orders`: normalizes mixed date formats via COALESCE
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
FROM `bipin-dev-project-465919`.`dbt_dgt_example`.`raw_orders`
WHERE order_id IS NOT NULL
  AND customer_id IS NOT NULL;


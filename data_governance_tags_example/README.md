# dbt Core 1.x + BigQuery Data Governance Tags — Complete Configurable Example

A complete **dbt Core 1.x** (`dbt-bigquery` REST `tables.patch`) project
demonstrating how to attach, update, clear, audit, and test **Google Cloud
BigQuery Data Governance Tags** (`purpose=DATA_GOVERNANCE` Resource Manager tags
+ BigQuery Data Policy API v2) with **fully configurable GCP project ID,
BigQuery dataset, location, and tag parent ID**.

> **Shared Code (`../common`):** Shared seeds (`raw_customers`, `raw_orders`),
> staging views (`stg_customers`, `stg_orders`), shared marts (`dim_customers`,
> `v_customers_public`), audit macro, singular test, GCP helper
> (`../common/scripts/manage_gcp_tags.py`), and Make targets
> (`../common/make/common.mk`) live in [`../common`](../common/dbt_project.yml)
> and are imported automatically via `packages.yml` (`local: ../common` / `dbt deps`).
> This folder contains **only** dbt Core 1.x-specific assets (nested `STRUCT` /
> `ARRAY<STRUCT>` leaf tags, nested model contract, Core `profiles.yml`, and SQL
> snapshot).

---

## What This Example Demonstrates

| dbt Resource | Location | Materialization | Governance Tag Pattern Covered |
|---|---|---|---|
| `raw_customers.csv` & `raw_orders.csv` | `../common/seeds/` | Seed tables (`dbt seed`) | Attaching `data_governance_tags` directly on ingestion seed tables via `properties.yml` |
| `stg_customers.sql` & `stg_orders.sql` | `../common/models/staging/` | Views | Column hygiene (`TRIM` preserving case, `SAFE_CAST`, `COALESCE` + `SAFE.PARSE_DATE`) + views with **descriptions only** |
| `dim_customers.sql` | `../common/models/marts/` | Table | Top-level scalar columns using **two distinct Tag Keys** + hierarchical leaf values (`email`, `ssn` under `pii`) |
| `fct_customer_profiles.sql` | `models/marts/` *(Core-specific)* | Incremental (`merge`) | **1-level `STRUCT`** (`profile.work_email`), **2-level `STRUCT<STRUCT>`** (`profile.identity.ssn`), **repeated `ARRAY<STRUCT>`** (`order_events.actor_email`), description-only parent `STRUCT`, and **explicit tag clearing** (`data_governance_tags: {}`) |
| `dim_customers_contracted.sql` | `models/marts/` *(Core-specific)* | Table (`contract: {enforced: true}`) | Combining strict dbt Model Contracts (`data_type`) with top-level and nested `STRUCT` leaf `data_governance_tags` |
| `v_customers_public.sql` | `../common/models/marts/` | View | Public non-PII analytics view coexisting cleanly with project-wide `persist_docs: {columns: true}` |
| `customers_snapshot.sql` | `snapshots/` *(Core-specific)* | SCD Type 2 Snapshot (`dbt snapshot`) | SQL `{% snapshot %}` persisting `data_governance_tags` on snapshot table columns |
| `audit_data_governance_tags.sql` | `../common/macros/` | Run-operation macro | Auditing attached column tags via `INFORMATION_SCHEMA.COLUMN_FIELD_PATHS` for the active `target.database`.`target.schema` |
| `*_test.yml` & `assert_positive_customer_ltv.sql` | `../common/` & `models/marts/` | Unit & Singular Tests | Unit tests for staging & mart transformations + schema & singular data tests |

---

## Configuration (Project Name, Dataset Name, Tag Parent)

All project, dataset, and tag namespace settings are driven by environment
variables (or `Makefile` / `--vars` overrides):

| Environment Variable | Default | Purpose |
|---|---|---|
| `GCP_PROJECT_ID` | `your-gcp-project-id` | Target BigQuery project in `profiles.yml` (and default Tag Key parent) |
| `BQ_DATASET` | `dbt_dgt_example` | Target BigQuery dataset in `profiles.yml` |
| `BQ_LOCATION` | `US` | BigQuery dataset and Data Policy API v2 location |
| `DBT_TARGET` | `dev` | Target in `profiles.yml` (`dev` or `prod`) |
| `DGT_PARENT_ID` | *(falls back to `GCP_PROJECT_ID`)* | Optional GCP Organization ID (e.g. `123456789012`) or central governance Project ID if your Tag Keys live outside `GCP_PROJECT_ID` |
| `DGT_CLASS_KEY_NAME` | `dbt_dgt_e2e_class` | Classification Tag Key `shortName` |
| `DGT_DOMAIN_KEY_NAME` | `dbt_dgt_e2e_domain` | Domain Tag Key `shortName` |

### Export environment variables (or use `.env`)

```bash
cp .env.example .env
# Edit .env with your GCP_PROJECT_ID and BQ_DATASET
set -a && source .env && set +a
```

### Option A: Pass variables via `make`

```bash
make compile PROJECT=my-gcp-project DATASET=my_dgt_demo
```

### Option B: Override tag keys/values at runtime with `--vars`

```bash
../.venv/bin/dbt compile --profiles-dir . \
  --vars '{"dgt_parent_id": "123456789012", "dgt_class_key_name": "data_classification"}'
```

---

## YAML Contract & Rules

Because BigQuery Data Governance Tag keys have the form `<parent_id>/<tag_key>`
and `dbt-core` 1.x renders Jinja in YAML dict *values* (not dict *keys*), this
project uses native Jinja dict rendering so `GCP_PROJECT_ID` / `DGT_PARENT_ID`
stay 100% configurable:

```yaml
columns:
  - name: email
    description: "Customer primary email address"
    data_governance_tags: "{{ { ((var('dgt_parent_id') or env_var('DGT_PARENT_ID', '') or target.database) ~ '/' ~ (var('dgt_class_key_name') or env_var('DGT_CLASS_KEY_NAME', '') or 'dbt_dgt_e2e_class')): var('dgt_email_tag_value') } }}"
```

If your Organization ID or governance project is static, you can also use plain
literal YAML keys:

```yaml
columns:
  - name: email
    data_governance_tags:
      123456789012/data_classification: email
```

### Key BigQuery & Adapter Rules

1. **Enable `persist_docs.columns: true`:** Configured globally in `dbt_project.yml` for models, seeds, and snapshots so `dbt-bigquery` patches column metadata and tags after materialization.
2. **Leaf `shortName` values only:** For hierarchical tags (`pii -> email`), always specify `email` — never `pii/email` (rejected with a fast-fail `CompilationError`).
3. **One tag per column:** BigQuery allows at most 1 Data Governance Tag per column, though sibling columns in the same table can use different Tag Keys (see `dim_customers`).
4. **No tags on views or `STRUCT` parents:** Attach tags only to table columns and leaf subfields (`profile.identity.ssn`), never on `VIEW` models or parent `RECORD`/`STRUCT` columns.
5. **Mutual exclusivity with legacy `policy_tags`:** Never specify both `policy_tags` and `data_governance_tags` on the same column. To migrate an existing incremental model in place without `--full-refresh`, replace `policy_tags` with `data_governance_tags` in `schema.yml` and run `dbt run` — `dbt-bigquery` swaps them atomically in a single `tables.patch` call.
6. **Clearing tags:** Set `data_governance_tags: {}` to explicitly clear tags on both `dbt-bigquery` (1.x) and `dbt` v2 / Fusion (or omit the property on `dbt-bigquery` 1.x to remove implicitly).

---

## Step-by-Step Walkthrough

### 1. Prerequisites (GCP Resource Manager Tags & Optional Masking Rules)

Your tag-owning GCP project must belong to a **GCP Organization** so Cloud
Resource Manager `purpose=DATA_GOVERNANCE` tag keys can be attached to BigQuery
columns.

**Using the included helper script (idempotent):**

```bash
# 1a. Provision DATA_GOVERNANCE Tag Keys/Values + target BigQuery dataset
make setup-gcp PROJECT=my-gcp-project DATASET=my_dgt_demo

# 1b. If the Tag Key already has (or will have) V2 Data Policies in this region,
#     grant your dbt runner leaf-level RAW_DATA_ACCESS_POLICY (email, ssn, public)
#     so `dbt run` reads raw source data without 403 errors or propagating masked strings:
make setup-gcp-raw-access PROJECT=my-gcp-project DATASET=my_dgt_demo

# 1c. (Optional) Bind dynamic masking for an analyst/BI principal (EMAIL_MASK on email,
#     SHA256 on ssn, and RAW_DATA_ACCESS_POLICY on public):
make setup-gcp-masked PROJECT=my-gcp-project DATASET=my_dgt_demo \
  GRANTEE="principal://goog/subject/analyst@example.com"
```

> **Important — Tag-Key Enforcement & Deepest-Tag-First Precedence:**
> - **Default-deny across sibling tag values:** Once *any* V2 Data Policy exists
>   for a Tag Key in a region (for example, `EMAIL_MASK` on `email`), BigQuery
>   enforces access control across **all** tag values under that Tag Key —
>   including non-PII sibling values like `public` (`loyalty_tier`). Without a
>   `RAW_DATA_ACCESS_POLICY` on `public`, querying `raw_customers.loyalty_tier`
>   fails with `403 Access Denied`.
> - **Why dbt runners need leaf-level `RAW_DATA_ACCESS_POLICY`:** BigQuery
>   evaluates V2 Data Policies **deepest-tag-first** (`RAW` beats `MASKED` only
>   at the same depth). Granting `RAW_DATA_ACCESS_POLICY` directly on `email`,
>   `ssn`, and `public` via `make setup-gcp-raw-access` ensures `dbt run` reads
>   unmasked source values cleanly while analysts remain masked. (Allow 1–5
>   minutes for newly created V2 Data Policies to propagate.)
> - **Clean isolation tip:** To avoid colliding with pre-existing policies on
>   `dbt_dgt_e2e_class`, you can also pass isolated Tag Key names:
>   `CLASS_KEY=dbt_dgt_example_class DOMAIN_KEY=dbt_dgt_example_domain`.

**Equivalent `gcloud` CLI commands:**

```bash
export GCP_PROJECT_ID="my-gcp-project"

# Classification Tag Key + hierarchical values (pii -> email, ssn; public)
gcloud resource-manager tags keys create dbt_dgt_e2e_class \
  --parent="projects/${GCP_PROJECT_ID}" \
  --purpose=DATA_GOVERNANCE
gcloud resource-manager tags values create pii \
  --parent="${GCP_PROJECT_ID}/dbt_dgt_e2e_class"
# Retrieve tagValues/<PII_ID> from the output above, then create child leaves:
gcloud resource-manager tags values create email --parent="tagValues/<PII_ID>"
gcloud resource-manager tags values create ssn   --parent="tagValues/<PII_ID>"
gcloud resource-manager tags values create public \
  --parent="${GCP_PROJECT_ID}/dbt_dgt_e2e_class"

# Domain Tag Key + finance leaf
gcloud resource-manager tags keys create dbt_dgt_e2e_domain \
  --parent="projects/${GCP_PROJECT_ID}" \
  --purpose=DATA_GOVERNANCE
gcloud resource-manager tags values create finance \
  --parent="${GCP_PROJECT_ID}/dbt_dgt_e2e_domain"
```

### 2. Compile & Verify Locally (No BigQuery Writes)

```bash
make compile PROJECT=my-gcp-project DATASET=my_dgt_demo
```

### 3. Materialize Seeds, Models, and Snapshots

```bash
make seed     PROJECT=my-gcp-project DATASET=my_dgt_demo
make run      PROJECT=my-gcp-project DATASET=my_dgt_demo
make snapshot PROJECT=my-gcp-project DATASET=my_dgt_demo
make test     PROJECT=my-gcp-project DATASET=my_dgt_demo
```

### 4. Inspect & Verify Attached Governance Tags in BigQuery

Using the built-in dbt run-operation macro:

```bash
make audit PROJECT=my-gcp-project DATASET=my_dgt_demo
```

Or run the automated assertion check against `INFORMATION_SCHEMA.COLUMN_FIELD_PATHS`:

```bash
make verify-gcp PROJECT=my-gcp-project DATASET=my_dgt_demo
```

Or query BigQuery directly:

```sql
SELECT
  table_name,
  field_path,
  data_type,
  ARRAY_TO_STRING(
    ARRAY(SELECT CONCAT(t.key, '=', t.value) FROM UNNEST(data_governance_tags) AS t),
    ', '
  ) AS data_governance_tags
FROM `<GCP_PROJECT_ID>`.`<BQ_DATASET>`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
WHERE ARRAY_LENGTH(data_governance_tags) > 0
ORDER BY table_name, field_path;
```

### 5. Clean Teardown (Tag-Hold Safe)

> **Important:** BigQuery enforces Resource Manager Tag Holds on active **and
> soft-deleted (time-travel)** tables. Always detach column tags *before*
> dropping tables if you plan to delete the underlying Tag Values later.

```bash
make teardown-gcp PROJECT=my-gcp-project DATASET=my_dgt_demo
```

---

## dbt Core 1.x (`dbt-bigquery`) vs dbt v2 / Fusion Notes

- **`dbt-bigquery` (`dbt-adapters` 1.x):** Uses BigQuery REST `tables.patch` inside `update_columns`. Supports top-level columns, arbitrary-depth nested `STRUCT` & repeated `ARRAY<STRUCT>` leaf fields, implicit & explicit (`{}`) tag removal, and single-call atomic `policy_tags` <-> `data_governance_tags` migration swaps.
- **`dbt` v2 / Fusion:** Uses a single batched `ALTER TABLE ... ALTER COLUMN ... SET OPTIONS (data_governance_tags=[...])` DDL statement. Supports top-level table columns and explicit `{}` clearing (`data_governance_tags=[]`); nested `STRUCT` leaf paths are rejected cleanly due to BigQuery `ALTER COLUMN` DDL constraints (omit nested leaf tags in `fct_customer_profiles` and `dim_customers_contracted` if targeting Fusion DDL-only mode).

# dbt v2 / Fusion + BigQuery Data Governance Tags — End-to-End Example

A complete **dbt v2 / Fusion** project demonstrating BigQuery column-level
**Data Governance Tags** (`data_governance_tags`) powered by the local
`feat/bigquery-data-governance-tags` branch in `../../dbt`, with **zero
hardcoded GCP project IDs or BigQuery dataset names**.

> **Shared Code (`../common`):** Shared seeds (`raw_customers`, `raw_orders`),
> staging views (`stg_customers`, `stg_orders`), shared marts (`dim_customers`,
> `v_customers_public`), audit macro, singular test, GCP helper
> (`../common/scripts/manage_gcp_tags.py`), and Make targets
> (`../common/make/common.mk`) live in [`../common`](../common/dbt_project.yml)
> and are imported automatically via `packages.yml` (`local: ../common` / `dbt deps`).
> This folder contains **only** dbt v2 / Fusion-specific assets (top-level PII
> modeling + described-only `STRUCT`, top-level model contract, YAML snapshot,
> Fusion `BigqueryDbConfig` profile, and `scripts/preview_fusion_ddl.py`).

---

## How dbt v2 / Fusion Applies Data Governance Tags

Unlike `dbt-bigquery` 1.x (which uses BigQuery REST `tables.patch` inside Python
`update_columns`), **dbt v2 / Fusion** deserializes `data_governance_tags` as a
first-class typed field (`Option<IndexMap<String, String>>` in `dbt-schemas` —
zero `CustomKeyInObjectDeprecation` warnings!) and persists tags inside
`bigquery__persist_docs` via a **single batched BigQuery DDL statement**:

```sql
alter table `<project>`.`<dataset>`.`dim_customers`
alter column `email` set options (data_governance_tags=[("<parent>/dbt_fusion_dgt_class", "email")]),
alter column `ssn` set options (data_governance_tags=[("<parent>/dbt_fusion_dgt_class", "ssn")]),
alter column `loyalty_tier` set options (data_governance_tags=[("<parent>/dbt_fusion_dgt_class", "public")]),
alter column `annual_income_usd` set options (data_governance_tags=[("<parent>/dbt_fusion_dgt_domain", "finance")]),
alter column `lifetime_spend_usd` set options (data_governance_tags=[("<parent>/dbt_fusion_dgt_domain", "finance")]);
```

### Key Fusion-Specific Behaviors Covered in This Example

| Capability / Rule | How This Example Demonstrates It |
|---|---|
| **First-class typed YAML (`Option<IndexMap<String, String>>`)** | Top-level `data_governance_tags:` on columns across seeds, models, and YAML snapshots (Fusion also accepts `config: {data_governance_tags: ...}`, with top-level taking precedence) |
| **Single batched `ALTER TABLE` DDL** | `dim_customers` tags 5 columns across 2 Tag Keys (`dbt_fusion_dgt_class` & `dbt_fusion_dgt_domain`) in one DDL statement |
| **Top-level PII + described-only `STRUCT`** | BigQuery `ALTER COLUMN` DDL does not accept dotted `STRUCT` leaf paths, so Fusion rejects dotted paths upfront. `fct_customer_profiles` models sensitive fields (`primary_email`, `work_email`, `ssn`, `latest_actor_email`) as top-level columns while storing non-PII attributes in a described-only `STRUCT` (`profile_metadata`) |
| **Explicit tag clearing (`data_governance_tags: {}`)** | Required in Fusion to remove an existing tag (omitting the property leaves existing tags untouched). `fct_customer_profiles.public_display_note` emits `alter column \`public_display_note\` set options (data_governance_tags=[])` |
| **Ordered rollback to legacy `policy_tags`** | Declaring `data_governance_tags: {}` alongside `policy_tags: [...]` triggers Fusion's 3-step sequence: **(1) pre-clear `data_governance_tags=[]` → (2) `adapter.update_columns` attaches `policy_tags` → (3) post-set DDL for remaining DGT columns** (verified in `scripts/preview_fusion_ddl.py`) |
| **Fusion-native YAML Snapshot** | `snapshots/schema.yml` uses modern YAML snapshot syntax (`relation: ref('dim_customers')`) with `persist_docs.columns: true` and `data_governance_tags` |
| **Fusion-strict `profiles.yml` & `dbt_project.yml`** | `profiles.yml` matches Fusion's `BigqueryDbConfig` (no unsupported `labels:` key in `profiles.yml`); BigQuery `+labels:` live on `models:`, `seeds:`, and `snapshots:` in `dbt_project.yml`; all generic tests nest params under `arguments:` |
| **Enforced model contracts (`contract: {enforced: true}`)** | `dim_customers_contracted` combines strict BigQuery `INT64`/`STRING` contracts with top-level `data_governance_tags` |
| **Views safely carry descriptions only** | `stg_customers`, `stg_orders`, and `v_customers_public` carry descriptions only (Fusion fails fast if any view declares non-empty `data_governance_tags`) |

---

## Configuration (Project, Dataset, Tag Parent)

All GCP project, dataset, location, and tag key names are configurable via
environment variables, `.env`, `make` variables, or `--vars`:

| Variable | Default | Purpose |
|---|---|---|
| `GCP_PROJECT_ID` (`PROJECT`) | `your-gcp-project-id` | Target BigQuery project in `profiles.yml` (and default Tag Key parent) |
| `BQ_DATASET` (`DATASET`) | `dbt_fusion_dgt_example` | Target BigQuery dataset in `profiles.yml` |
| `BQ_LOCATION` (`LOCATION`) | `US` | BigQuery dataset & Data Policy API v2 location |
| `DBT_TARGET` (`TARGET`) | `dev` | Target in `profiles.yml` (`dev` or `prod`) |
| `DGT_PARENT_ID` (`DGT_PARENT`) | *(falls back to `target.database`)* | Optional GCP Organization ID (e.g. `123456789012`) or central governance project |
| `DGT_CLASS_KEY_NAME` (`CLASS_KEY`) | `dbt_fusion_dgt_class` | Isolated classification Tag Key `shortName` |
| `DGT_DOMAIN_KEY_NAME` (`DOMAIN_KEY`) | `dbt_fusion_dgt_domain` | Isolated domain Tag Key `shortName` |
| `DBT_FUSION_BIN` | `../../dbt/target/release/dbt` | Path to your compiled local dbt v2 / Fusion binary |

> **Tip for Organization-level Tag Keys:** If your Tag Keys live at the GCP
> Organization level (`123456789012/data_class`), the key is identical across
> dev/staging/prod, so you can replace the single-expression Jinja dict
> (`"{{ { ... } }}"`) with plain static YAML keys:
> ```yaml
> data_governance_tags:
>   123456789012/data_class: email
> ```

---

## End-to-End Walkthrough

### Step 1: Build the Local dbt v2 / Fusion Binary (and Run Fusion Rust Tests)

Requires the Rust toolchain (`rustup` / `cargo` — see `../../dbt/CONTRIBUTING.md`):

```bash
# Build local dbt v2 / Fusion binary from ../../dbt (branch: feat/bigquery-data-governance-tags)
make build-fusion          # builds ../../dbt/target/release/dbt
# (Or `make build-fusion-debug` for a faster debug build at ../../dbt/target/debug/dbt)

# Verify the local Fusion Rust unit & macro test suites pass
make test-fusion-rust
```

### Step 2: Preview & Validate Exact Fusion DDL Offline (Works Even Before Building Rust!)

This loads the **exact `bigquery__persist_docs` and
`bigquery__get_alter_column_data_governance_tags_sql` macros** directly from
`../../dbt/crates/dbt-loader/src/dbt_macro_assets/dbt-bigquery/macros/adapters.sql`
and verifies all generated `ALTER TABLE` statements, Fusion's 3-step ordered
rollback sequence, and all 6 Fusion fast-fail validation guards:

```bash
make preview-ddl PROJECT=<your-gcp-project-id> DATASET=<your-bq-dataset>
```

### Step 3: Provision GCP Data Governance Tags & Dataset

Your tag-owning GCP project must belong to a **GCP Organization** so Cloud
Resource Manager `purpose=DATA_GOVERNANCE` Tag Keys can be attached to BigQuery
columns.

```bash
# 3a. Provision isolated DATA_GOVERNANCE Tag Keys/Values + BigQuery dataset
make setup-gcp PROJECT=<your-gcp-project-id> DATASET=<your-bq-dataset>

# 3b. (Optional — required whenever V2 Data Policies exist on CLASS_KEY in this region)
#     Grant your dbt runner leaf-level RAW_DATA_ACCESS_POLICY on email, ssn, and public:
make setup-gcp-raw-access PROJECT=<your-gcp-project-id> DATASET=<your-bq-dataset>

# 3c. (Optional) Bind dynamic masking for an analyst/BI principal
#     (EMAIL_MASK on email, SHA256 on ssn, RAW_DATA_ACCESS_POLICY on public):
make setup-gcp-masked PROJECT=<your-gcp-project-id> DATASET=<your-bq-dataset> \
  GRANTEE="principal://goog/subject/analyst@example.com"
```

> **Enforcement & Precedence Reminder:**
> - Once *any* V2 Data Policy exists on a Tag Key in a region, BigQuery enforces
>   default-deny across **all** tag values of that Tag Key (including `public`).
> - BigQuery evaluates V2 policies **deepest-tag-first** (`RAW` beats `MASKED`
>   only at the same depth), so dbt runners need leaf-level
>   `RAW_DATA_ACCESS_POLICY` on `email`, `ssn`, and `public` whenever masking
>   policies are active. Allow 1–5 minutes for newly created V2 Data Policies to
>   propagate.

### Step 4: Execute the Full Pipeline with dbt v2 / Fusion

```bash
# Compile (no BigQuery writes)
make compile PROJECT=<your-gcp-project-id> DATASET=<your-bq-dataset>

# Run the complete pipeline: seed -> run -> snapshot -> test -> audit
make all PROJECT=<your-gcp-project-id> DATASET=<your-bq-dataset>

# Assert all 25 expected columns in INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
make verify-gcp PROJECT=<your-gcp-project-id> DATASET=<your-bq-dataset>
```

### Step 5: Test Incremental Tag Update, Explicit Clear, or Ordered Rollback

On `fct_customer_profiles` (incremental merge, **without `--full-refresh`**):

1. **Update a tag value:** Change `primary_email`'s value from `email` to `public` in `models/marts/schema.yml` and run `make run`. Fusion emits `alter column \`primary_email\` set options (data_governance_tags=[("<parent>/dbt_fusion_dgt_class", "public")])`.
2. **Clear a tag explicitly:** Set `data_governance_tags: {}` (like `public_display_note`). Fusion emits `alter column ... set options (data_governance_tags=[])`.
3. **Roll back a column to legacy `policy_tags`:** Specify both `data_governance_tags: {}` and `policy_tags: ["projects/.../policyTags/..."]` on that column in `schema.yml` and run `make run`. Fusion automatically runs pre-clear DDL first, then attaches `policy_tags` via `update_columns`, then applies any remaining sibling column DGTs.

### Step 6: Clean Teardown (Tag-Hold Safe)

BigQuery enforces Resource Manager Tag Holds on active **and soft-deleted
(time-travel)** tables. `teardown-gcp` detaches all column tags *before*
dropping the dataset and deleting temporary V2 policies:

```bash
make teardown-gcp PROJECT=<your-gcp-project-id> DATASET=<your-bq-dataset>
```

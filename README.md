# BigQuery Data Governance Tags — dbt Examples (`dbt Core 1.x` & `dbt v2 / Fusion`)

This directory contains two side-by-side end-to-end dbt examples sharing a
common local dbt package and GCP/Make tooling with zero duplicated code:

```text
dbt_example/
├── common/                                # Shared local dbt package (`dbt_dgt_common`) + shared tooling
│   ├── dbt_project.yml
│   ├── seeds/                             # raw_customers.csv, raw_orders.csv, properties.yml
│   ├── models/
│   │   ├── staging/                       # stg_customers, stg_orders, schema.yml, unit tests
│   │   └── marts/                         # dim_customers, v_customers_public, schema.yml, unit test
│   ├── macros/                            # audit_data_governance_tags.sql
│   ├── tests/                             # assert_positive_customer_ltv.sql
│   ├── scripts/                           # manage_gcp_tags.py (--mode core|fusion)
│   └── make/                              # common.mk (shared Make targets)
│
├── data_governance_tags_example/          # dbt Core 1.x (`dbt-bigquery` REST `tables.patch`)
│   ├── packages.yml                       # local: ../common
│   ├── models/marts/                      # Nested STRUCT / ARRAY<STRUCT> leaf tags + nested contract
│   └── snapshots/                         # SQL `{% snapshot %}` block
│
└── fusion_data_governance_tags_example/   # dbt v2 / Fusion (batched `ALTER TABLE ... ALTER COLUMN` DDL)
    ├── packages.yml                       # local: ../common
    ├── models/marts/                      # Top-level PII + described-only STRUCT + top-level contract
    ├── snapshots/                         # Fusion YAML-defined snapshot (`relation: ref('dim_customers')`)
    └── scripts/                           # preview_fusion_ddl.py (offline Fusion DDL & rollback verifier)
```

## Quick Start

Both examples keep `PROJECT` (`GCP_PROJECT_ID`), `DATASET` (`BQ_DATASET`),
`LOCATION` (`BQ_LOCATION`), and `DGT_PARENT` (`DGT_PARENT_ID`) 100% configurable
and automatically install `../common` via `dbt deps`.

- **dbt Core 1.x (`dbt-bigquery` REST `tables.patch`):** see [`data_governance_tags_example/README.md`](./data_governance_tags_example/README.md)
- **dbt v2 / Fusion (batched `ALTER TABLE` DDL):** see [`fusion_data_governance_tags_example/README.md`](./fusion_data_governance_tags_example/README.md)

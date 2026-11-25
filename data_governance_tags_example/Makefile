# dbt Core 1.x (`dbt-bigquery` REST `tables.patch`) Data Governance Tags example.
# Shared targets & GCP helper live in ../common/make/common.mk.

DBT_BIN ?= ../../.venv/bin/dbt
EXAMPLE_MODE := core
DEFAULT_DATASET := dbt_dgt_example
DEFAULT_CLASS_KEY := dbt_dgt_e2e_class
DEFAULT_DOMAIN_KEY := dbt_dgt_e2e_domain
POLICY_PREFIX := dbt_dgt_example

include ../common/make/common.mk

.PHONY: help

help:
	@echo "dbt Core 1.x Binary: $(DBT_BIN)"
	@echo "Shared package:      ../common (dbt_dgt_common)"
	@echo ""
	@echo "Configurable variables:"
	@echo "  PROJECT     BigQuery GCP project ID (or env GCP_PROJECT_ID)"
	@echo "  DATASET     BigQuery dataset name   (default: $(DEFAULT_DATASET))"
	@echo "  LOCATION    BigQuery location       (default: US)"
	@echo "  DGT_PARENT  Optional TagKey parent  (defaults to PROJECT; can be Org ID)"
	@echo "  CLASS_KEY   Classification TagKey   (default: $(DEFAULT_CLASS_KEY))"
	@echo "  DOMAIN_KEY  Domain TagKey           (default: $(DEFAULT_DOMAIN_KEY))"
	@echo "  GRANTEE     Optional IAM v3 URI for setup-gcp-raw-access / setup-gcp-masked"
	@echo ""
	@echo "Targets:"
	@echo "  make deps                 Install local ../common dbt package"
	@echo "  make compile              Compile all models, snapshots, and unit tests (no BQ writes)"
	@echo "  make debug                Verify dbt profile & BigQuery connectivity"
	@echo "  make setup-gcp            Provision DATA_GOVERNANCE Tag Keys/Values & dataset in GCP"
	@echo "  make setup-gcp-raw-access Provision tags + grant dbt runner RAW_DATA_ACCESS_POLICY (email, ssn, public)"
	@echo "  make setup-gcp-masked     Provision tags + bind EMAIL_MASK, SHA256, and public raw access"
	@echo "  make seed                 Run dbt seed (attaches DGT to raw_customers & raw_orders)"
	@echo "  make run                  Run dbt models (shared + nested STRUCT / ARRAY<STRUCT> marts)"
	@echo "  make snapshot             Run dbt snapshot (SQL snapshot + DGT)"
	@echo "  make test                 Run dbt schema, singular, and unit tests"
	@echo "  make audit                Run shared audit_data_governance_tags macro"
	@echo "  make verify-gcp           Assert all expected Core DGTs in INFORMATION_SCHEMA"
	@echo "  make all                  Run seed -> run -> snapshot -> test -> audit"
	@echo "  make teardown-gcp         Detach column tags & drop DATASET + temporary V2 policies"

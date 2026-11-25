# dbt v2 / Fusion batched `ALTER TABLE` Data Governance Tags example.
# Shared targets & GCP helper live in ../common/make/common.mk.

FUSION_REPO ?= ../../dbt
CORE_DBT ?= ../../.venv/bin/dbt

# Prefer the locally built Fusion binary from ../../dbt; fall back to `dbt` on PATH.
DBT_FUSION_BIN ?= $(firstword $(wildcard $(FUSION_REPO)/target/release/dbt) $(wildcard $(FUSION_REPO)/target/debug/dbt) dbt)
DBT_BIN := $(DBT_FUSION_BIN)

EXAMPLE_MODE := fusion
DEFAULT_DATASET := dbt_fusion_dgt_example
DEFAULT_CLASS_KEY := dbt_fusion_dgt_class
DEFAULT_DOMAIN_KEY := dbt_fusion_dgt_domain
POLICY_PREFIX := dbt_fusion_dgt

include ../common/make/common.mk

.PHONY: help build-fusion build-fusion-debug test-fusion-rust preview-ddl

help:
	@echo "dbt v2 / Fusion Binary: $(DBT_FUSION_BIN)"
	@echo "Shared package:         ../common (dbt_dgt_common)"
	@echo ""
	@echo "Configurable variables:"
	@echo "  PROJECT        BigQuery GCP project ID (or env GCP_PROJECT_ID)"
	@echo "  DATASET        BigQuery dataset name   (default: $(DEFAULT_DATASET))"
	@echo "  LOCATION       BigQuery location       (default: US)"
	@echo "  DGT_PARENT     Optional TagKey parent  (defaults to PROJECT; can be Org ID)"
	@echo "  CLASS_KEY      Classification TagKey   (default: $(DEFAULT_CLASS_KEY))"
	@echo "  DOMAIN_KEY     Domain TagKey           (default: $(DEFAULT_DOMAIN_KEY))"
	@echo "  GRANTEE        Optional IAM v3 URI for V2 Data Policies"
	@echo "  DBT_FUSION_BIN Override path to dbt v2 / Fusion binary"
	@echo ""
	@echo "Fusion Build & Verification Targets:"
	@echo "  make build-fusion         Build local Fusion release binary (cargo build --release -p dbt-sa-cli --bin dbt)"
	@echo "  make build-fusion-debug   Build local Fusion debug binary (faster compile)"
	@echo "  make test-fusion-rust     Run all Fusion Rust data_governance_tags test suites"
	@echo "  make preview-ddl          Render & validate exact Fusion ALTER TABLE DDL, rollback & guards offline"
	@echo ""
	@echo "GCP & dbt v2 / Fusion Execution Targets (from ../common/make/common.mk):"
	@echo "  make deps                 Install local ../common dbt package"
	@echo "  make setup-gcp            Provision DATA_GOVERNANCE Tag Keys/Values & dataset in GCP"
	@echo "  make setup-gcp-raw-access Provision tags + grant dbt runner leaf RAW_DATA_ACCESS_POLICY (email, ssn, public)"
	@echo "  make setup-gcp-masked     Provision tags + bind EMAIL_MASK, SHA256, and public raw access"
	@echo "  make compile | seed | run | snapshot | test | audit | all | verify-gcp | teardown-gcp"

build-fusion:
	cargo build --manifest-path "$(FUSION_REPO)/Cargo.toml" --release -p dbt-sa-cli --bin dbt

build-fusion-debug:
	cargo build --manifest-path "$(FUSION_REPO)/Cargo.toml" -p dbt-sa-cli --bin dbt

test-fusion-rust:
	cargo test --manifest-path "$(FUSION_REPO)/Cargo.toml" -p dbt-schemas data_governance_tags
	cargo test --manifest-path "$(FUSION_REPO)/Cargo.toml" -p dbt-adapter --lib update_columns
	cargo test --manifest-path "$(FUSION_REPO)/Cargo.toml" -p dbt-loader --test main data_governance_tags

# Renders exact Fusion ALTER TABLE DDL directly from ../../dbt/.../adapters.sql
# using target/manifest.json (uses Fusion binary if available, else local dbt-core).
preview-ddl:
	@if [ -x "$(DBT_FUSION_BIN)" ] || command -v "$(DBT_FUSION_BIN)" >/dev/null 2>&1; then \
		if [ ! -e "dbt_packages/dbt_dgt_common" ]; then $(DBT_ENV) $(DBT_FUSION_BIN) deps $(DBT_FLAGS); fi; \
		$(DBT_ENV) $(DBT_FUSION_BIN) compile $(DBT_FLAGS); \
	else \
		if [ ! -e "dbt_packages/dbt_dgt_common" ]; then $(DBT_ENV) $(CORE_DBT) deps $(DBT_FLAGS) --no-use-colors -q; fi; \
		$(DBT_ENV) $(CORE_DBT) compile $(DBT_FLAGS) --no-use-colors -q; \
	fi
	$(PYTHON) scripts/preview_fusion_ddl.py \
		--manifest target/manifest.json \
		--adapters-sql "$(FUSION_REPO)/crates/dbt-loader/src/dbt_macro_assets/dbt-bigquery/macros/adapters.sql"

# Convenience targets for running the dbt Data Governance Tags example with
# configurable GCP project ID, BigQuery dataset, location, and tag parent ID.
#
# Examples:
#   make compile PROJECT=my-gcp-project DATASET=my_dgt_demo
#   make setup-gcp PROJECT=my-gcp-project DATASET=my_dgt_demo
#   make all PROJECT=my-gcp-project DATASET=my_dgt_demo
#   make verify-gcp PROJECT=my-gcp-project DATASET=my_dgt_demo

DBT ?= ../.venv/bin/dbt
PYTHON ?= ../.venv/bin/python

PROJECT ?= $(GCP_PROJECT_ID)
DATASET ?= $(or $(BQ_DATASET),dbt_dgt_example)
LOCATION ?= $(or $(BQ_LOCATION),US)
DGT_PARENT ?= $(DGT_PARENT_ID)
CLASS_KEY ?= $(or $(DGT_CLASS_KEY_NAME),dbt_dgt_e2e_class)
DOMAIN_KEY ?= $(or $(DGT_DOMAIN_KEY_NAME),dbt_dgt_e2e_domain)
TARGET ?= $(or $(DBT_TARGET),dev)

DBT_ENV := GCP_PROJECT_ID="$(PROJECT)" \
           BQ_DATASET="$(DATASET)" \
           BQ_LOCATION="$(LOCATION)" \
           DGT_PARENT_ID="$(DGT_PARENT)" \
           DGT_CLASS_KEY_NAME="$(CLASS_KEY)" \
           DGT_DOMAIN_KEY_NAME="$(DOMAIN_KEY)" \
           DBT_TARGET="$(TARGET)"

DBT_FLAGS := --profiles-dir .

GRANTEE ?=

.PHONY: help compile parse debug seed run snapshot test audit all setup-gcp setup-gcp-raw-access setup-gcp-masked verify-gcp teardown-gcp clean

help:
	@echo "Configurable variables:"
	@echo "  PROJECT     BigQuery GCP project ID (or env GCP_PROJECT_ID)"
	@echo "  DATASET     BigQuery dataset name   (default: dbt_dgt_example)"
	@echo "  LOCATION    BigQuery location       (default: US)"
	@echo "  DGT_PARENT  Optional TagKey parent  (defaults to PROJECT; can be Org ID)"
	@echo "  CLASS_KEY   Classification TagKey   (default: dbt_dgt_e2e_class)"
	@echo "  DOMAIN_KEY  Domain TagKey           (default: dbt_dgt_e2e_domain)"
	@echo "  GRANTEE     Optional IAM v3 URI for setup-gcp-raw-access / setup-gcp-masked"
	@echo ""
	@echo "Targets:"
	@echo "  make compile              Compile all models, snapshots, and unit tests (no BQ writes)"
	@echo "  make debug                Verify dbt profile & BigQuery connectivity"
	@echo "  make setup-gcp            Provision DATA_GOVERNANCE Tag Keys/Values & dataset in GCP"
	@echo "  make setup-gcp-raw-access Provision tags + grant dbt runner RAW_DATA_ACCESS_POLICY (email, ssn, public)"
	@echo "  make setup-gcp-masked     Provision tags + bind EMAIL_MASK, SHA256, and public raw access"
	@echo "  make seed                 Run dbt seed (attaches DGT to raw_customers & raw_orders)"
	@echo "  make run                  Run dbt models (table, incremental+nested, contract, views)"
	@echo "  make snapshot             Run dbt snapshot (attaches DGT to SCD-2 snapshot)"
	@echo "  make test                 Run dbt schema, singular, and unit tests"
	@echo "  make audit                Run dbt audit_data_governance_tags macro"
	@echo "  make verify-gcp           Assert all expected DGTs in INFORMATION_SCHEMA"
	@echo "  make all                  Run seed -> run -> snapshot -> test -> audit"
	@echo "  make teardown-gcp         Detach column tags & drop DATASET + temporary V2 policies"

compile:
	$(DBT_ENV) $(DBT) compile $(DBT_FLAGS)

parse:
	$(DBT_ENV) $(DBT) parse $(DBT_FLAGS)

debug:
	$(DBT_ENV) $(DBT) debug $(DBT_FLAGS)

seed:
	$(DBT_ENV) $(DBT) seed $(DBT_FLAGS)

run:
	$(DBT_ENV) $(DBT) run $(DBT_FLAGS)

snapshot:
	$(DBT_ENV) $(DBT) snapshot $(DBT_FLAGS)

test:
	$(DBT_ENV) $(DBT) test $(DBT_FLAGS)

audit:
	$(DBT_ENV) $(DBT) run-operation audit_data_governance_tags $(DBT_FLAGS)

all: seed run snapshot test audit

setup-gcp:
	$(DBT_ENV) $(PYTHON) scripts/manage_gcp_tags.py \
		--project "$(PROJECT)" --dataset "$(DATASET)" --location "$(LOCATION)" \
		--class-key-name "$(CLASS_KEY)" --domain-key-name "$(DOMAIN_KEY)" \
		setup $(if $(DGT_PARENT),--tag-project "$(DGT_PARENT)",)

setup-gcp-raw-access:
	$(DBT_ENV) $(PYTHON) scripts/manage_gcp_tags.py \
		--project "$(PROJECT)" --dataset "$(DATASET)" --location "$(LOCATION)" \
		--class-key-name "$(CLASS_KEY)" --domain-key-name "$(DOMAIN_KEY)" \
		setup --with-raw-access-policies \
		$(if $(DGT_PARENT),--tag-project "$(DGT_PARENT)",) \
		$(if $(GRANTEE),--grantee "$(GRANTEE)",)

setup-gcp-masked:
	$(DBT_ENV) $(PYTHON) scripts/manage_gcp_tags.py \
		--project "$(PROJECT)" --dataset "$(DATASET)" --location "$(LOCATION)" \
		--class-key-name "$(CLASS_KEY)" --domain-key-name "$(DOMAIN_KEY)" \
		setup --with-masking-policies \
		$(if $(DGT_PARENT),--tag-project "$(DGT_PARENT)",) \
		$(if $(GRANTEE),--grantee "$(GRANTEE)",)

verify-gcp:
	$(DBT_ENV) $(PYTHON) scripts/manage_gcp_tags.py \
		--project "$(PROJECT)" --dataset "$(DATASET)" --location "$(LOCATION)" \
		--class-key-name "$(CLASS_KEY)" --domain-key-name "$(DOMAIN_KEY)" \
		verify $(if $(DGT_PARENT),--tag-parent "$(DGT_PARENT)",)

teardown-gcp:
	$(DBT_ENV) $(PYTHON) scripts/manage_gcp_tags.py \
		--project "$(PROJECT)" --dataset "$(DATASET)" --location "$(LOCATION)" \
		teardown --yes

clean:
	$(DBT_ENV) $(DBT) clean $(DBT_FLAGS)

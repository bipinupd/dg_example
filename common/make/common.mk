# Shared Makefile fragment included by both:
#   - data_governance_tags_example/Makefile        (EXAMPLE_MODE=core)
#   - fusion_data_governance_tags_example/Makefile (EXAMPLE_MODE=fusion)
#
# Expected caller variables (set before `include ../common/make/common.mk`):
#   DBT_BIN             dbt executable to run
#   EXAMPLE_MODE        core | fusion
#   DEFAULT_DATASET     default BigQuery dataset name
#   DEFAULT_CLASS_KEY   default classification TagKey shortName
#   DEFAULT_DOMAIN_KEY  default domain TagKey shortName
#   POLICY_PREFIX       prefix for optional V2 Data Policy IDs

COMMON_DIR ?= ../common
PYTHON ?= ../../.venv/bin/python

PROJECT ?= $(GCP_PROJECT_ID)
DATASET ?= $(or $(BQ_DATASET),$(DEFAULT_DATASET))
LOCATION ?= $(or $(BQ_LOCATION),US)
DGT_PARENT ?= $(DGT_PARENT_ID)
CLASS_KEY ?= $(or $(DGT_CLASS_KEY_NAME),$(DEFAULT_CLASS_KEY))
DOMAIN_KEY ?= $(or $(DGT_DOMAIN_KEY_NAME),$(DEFAULT_DOMAIN_KEY))
TARGET ?= $(or $(DBT_TARGET),dev)
GRANTEE ?=

DBT_ENV := GCP_PROJECT_ID="$(PROJECT)" \
           BQ_DATASET="$(DATASET)" \
           BQ_LOCATION="$(LOCATION)" \
           DGT_PARENT_ID="$(DGT_PARENT)" \
           DGT_CLASS_KEY_NAME="$(CLASS_KEY)" \
           DGT_DOMAIN_KEY_NAME="$(DOMAIN_KEY)" \
           DBT_TARGET="$(TARGET)"

DBT_FLAGS := --profiles-dir .

GCP_HELPER := $(PYTHON) $(COMMON_DIR)/scripts/manage_gcp_tags.py \
              --mode "$(EXAMPLE_MODE)" \
              --project "$(PROJECT)" \
              --dataset "$(DATASET)" \
              --location "$(LOCATION)" \
              --class-key-name "$(CLASS_KEY)" \
              --domain-key-name "$(DOMAIN_KEY)" \
              --policy-prefix "$(POLICY_PREFIX)"

.PHONY: deps ensure-deps compile parse debug seed run snapshot test audit all \
        setup-gcp setup-gcp-raw-access setup-gcp-masked verify-gcp teardown-gcp clean

deps:
	$(DBT_ENV) $(DBT_BIN) deps $(DBT_FLAGS)

ensure-deps:
	@if [ ! -e "dbt_packages/dbt_dgt_common" ]; then \
		$(DBT_ENV) $(DBT_BIN) deps $(DBT_FLAGS); \
	fi

compile: ensure-deps
	$(DBT_ENV) $(DBT_BIN) compile $(DBT_FLAGS)

parse: ensure-deps
	$(DBT_ENV) $(DBT_BIN) parse $(DBT_FLAGS)

debug:
	$(DBT_ENV) $(DBT_BIN) debug $(DBT_FLAGS)

seed: ensure-deps
	$(DBT_ENV) $(DBT_BIN) seed $(DBT_FLAGS)

run: ensure-deps
	$(DBT_ENV) $(DBT_BIN) run $(DBT_FLAGS)

snapshot: ensure-deps
	$(DBT_ENV) $(DBT_BIN) snapshot $(DBT_FLAGS)

test: ensure-deps
	$(DBT_ENV) $(DBT_BIN) test $(DBT_FLAGS)

audit: ensure-deps
	$(DBT_ENV) $(DBT_BIN) run-operation audit_data_governance_tags $(DBT_FLAGS)

all: seed run snapshot test audit

setup-gcp:
	$(DBT_ENV) $(GCP_HELPER) setup $(if $(DGT_PARENT),--tag-project "$(DGT_PARENT)",)

setup-gcp-raw-access:
	$(DBT_ENV) $(GCP_HELPER) setup --with-raw-access-policies \
		$(if $(DGT_PARENT),--tag-project "$(DGT_PARENT)",) \
		$(if $(GRANTEE),--grantee "$(GRANTEE)",)

setup-gcp-masked:
	$(DBT_ENV) $(GCP_HELPER) setup --with-masking-policies \
		$(if $(DGT_PARENT),--tag-project "$(DGT_PARENT)",) \
		$(if $(GRANTEE),--grantee "$(GRANTEE)",)

verify-gcp:
	$(DBT_ENV) $(GCP_HELPER) verify $(if $(DGT_PARENT),--tag-parent "$(DGT_PARENT)",)

teardown-gcp:
	$(DBT_ENV) $(GCP_HELPER) teardown --yes

clean:
	rm -rf target dbt_packages package-lock.yml logs

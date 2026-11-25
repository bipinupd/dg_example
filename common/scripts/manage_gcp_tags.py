#!/usr/bin/env python3
"""Zero-dependency GCP helper for the dbt Core 1.x & dbt v2 / Fusion DGT examples.

Uses ONLY Python 3 standard library (`urllib`, `json`, `subprocess`).
Obtains an OAuth access token via `google-auth` if available, or falls back
automatically to `gcloud auth application-default print-access-token` /
`gcloud auth print-access-token` — so it works on any Fusion VM with zero venv
or pip installs.

Subcommands:
  setup     Idempotently provision DATA_GOVERNANCE Tag Keys/Values, dataset,
            and optional BigQuery Data Policy API v2 masking/raw-access rules.
  verify    Inspect INFORMATION_SCHEMA.COLUMN_FIELD_PATHS in <project>.<dataset>
            and verify every expected Data Governance Tag for `--mode core|fusion`.
  teardown  Safely detach column tags BEFORE dropping <project>.<dataset> and
            temporary V2 policies (prevents GCP Resource Manager Tag Hold locks).
"""

from __future__ import annotations

import argparse
import copy
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Dict, List, Optional, Tuple

CRM_V3 = "https://cloudresourcemanager.googleapis.com/v3"
DP_V2 = "https://bigquerydatapolicy.googleapis.com/v2"
BQ_V2 = "https://bigquery.googleapis.com/bigquery/v2"

_PROJECT_RE = re.compile(r"^[a-z][a-z0-9-]{4,28}[a-z0-9]$")
_DATASET_RE = re.compile(r"^[A-Za-z0-9_]{1,1024}$")
_LOCATION_RE = re.compile(r"^[A-Za-z0-9-]{2,32}$")
_TAG_SHORT_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_-]{0,62}$")
_POLICY_PREFIX_RE = re.compile(r"^[A-Za-z0-9_]{1,40}$")
_PRINCIPAL_RE = re.compile(r"^(principal|principalSet)://\S+$")

_CACHED_TOKEN: Optional[Tuple[str, Optional[str]]] = None


def _labels_for_mode(mode: str) -> Dict[str, str]:
    example = "dbt_fusion_dgt" if mode == "fusion" else "dbt_data_governance_tags"
    return {"datacloud": "antigravity", "example": example}


def _validate(name: str, value: str, pattern: re.Pattern[str]) -> str:
    if not value or not pattern.match(value):
        raise ValueError(f"Invalid {name}: {value!r}")
    return value


def _validate_project(project_id: str) -> str:
    if project_id == "your-gcp-project-id":
        raise ValueError(
            "Placeholder project ID 'your-gcp-project-id' detected. "
            "Pass --project <GCP_PROJECT_ID> or export GCP_PROJECT_ID."
        )
    return _validate("project ID", project_id, _PROJECT_RE)


def _get_access_token() -> Tuple[str, Optional[str]]:
    """Return `(access_token, service_account_email_or_none)` using stdlib fallback."""
    global _CACHED_TOKEN
    if _CACHED_TOKEN is not None:
        return _CACHED_TOKEN

    # 1. Prefer google-auth when installed (e.g. inside a dbt Core virtualenv).
    try:
        import google.auth  # type: ignore[import-not-found]
        import google.auth.transport.requests  # type: ignore[import-not-found]

        creds, _ = google.auth.default(
            scopes=["https://www.googleapis.com/auth/cloud-platform"]
        )
        creds.refresh(google.auth.transport.requests.Request())
        if creds.token:
            sa_email = getattr(creds, "service_account_email", None)
            if sa_email == "default":
                sa_email = None
            _CACHED_TOKEN = (creds.token, sa_email)
            return _CACHED_TOKEN
    except Exception:
        pass

    # 2. Pure-stdlib fallback via `gcloud` CLI (works on Fusion VMs without pip).
    gcloud_bin = shutil.which("gcloud")
    if not gcloud_bin:
        raise RuntimeError(
            "Neither `google-auth` nor `gcloud` CLI is available to obtain an "
            "access token. Install gcloud CLI or pass PYTHON=/path/to/venv/bin/python."
        )

    env = os.environ.copy()
    existing_metrics = env.get("CLOUDSDK_METRICS_ENVIRONMENT", "").strip()
    env["CLOUDSDK_METRICS_ENVIRONMENT"] = (
        f"{existing_metrics} datacloud.antigravity"
        if existing_metrics
        else "datacloud.antigravity"
    )

    for cmd in (
        [gcloud_bin, "auth", "application-default", "print-access-token"],
        [gcloud_bin, "auth", "print-access-token"],
    ):
        proc = subprocess.run(
            cmd, capture_output=True, text=True, env=env, timeout=20, check=False
        )
        token = (proc.stdout or "").strip()
        if proc.returncode == 0 and token:
            _CACHED_TOKEN = (token, None)
            return _CACHED_TOKEN

    raise RuntimeError(
        "Failed to obtain Google Cloud access token. Run "
        "`gcloud auth application-default login` (or `gcloud auth login`)."
    )


def _gcp_rest(
    method: str,
    url: str,
    body: Optional[Dict[str, Any]] = None,
    *,
    allow_not_found: bool = False,
    allow_conflict: bool = False,
) -> Optional[Dict[str, Any]]:
    allowed_prefixes = (CRM_V3 + "/", DP_V2 + "/", BQ_V2 + "/")
    if not url.startswith(allowed_prefixes):
        raise ValueError("Refusing request to unexpected API endpoint.")
    token, _ = _get_access_token()
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }
    data = json.dumps(body).encode("utf-8") if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=60) as resp:
            raw = resp.read().decode("utf-8")
            return json.loads(raw) if raw else {}
    except urllib.error.HTTPError as exc:
        err = exc.read().decode("utf-8", errors="replace")
        if allow_not_found and exc.code == 404:
            return None
        if allow_conflict and exc.code == 409:
            return None
        raise RuntimeError(f"{method} {url} failed ({exc.code}): {err}") from exc


def _wait_crm_lro(op_data: Dict[str, Any], timeout_s: float = 60.0) -> Dict[str, Any]:
    if op_data.get("done"):
        if "error" in op_data:
            raise RuntimeError(f"Operation failed: {op_data['error']}")
        return op_data.get("response", op_data)
    op_name = op_data["name"]
    deadline = time.time() + timeout_s
    while time.time() < deadline:
        time.sleep(1.0)
        status = _gcp_rest("GET", f"{CRM_V3}/{op_name}")
        if status and status.get("done"):
            if "error" in status:
                raise RuntimeError(f"Operation {op_name} failed: {status['error']}")
            return status.get("response", status)
    raise TimeoutError(f"Timed out waiting for CRM operation {op_name}")


def _resolve_project_number(project_id: str) -> str:
    proj = _gcp_rest(
        "GET", f"{CRM_V3}/projects/{urllib.parse.quote(project_id, safe='')}"
    )
    if not proj or "name" not in proj:
        raise RuntimeError(f"Could not resolve project number for {project_id}")
    return proj["name"].split("/", 1)[1]


def _get_active_iam_v3_principal() -> str:
    token, sa_email = _get_access_token()
    if sa_email:
        return f"principal://iam.googleapis.com/projects/-/serviceAccounts/{sa_email}"
    req = urllib.request.Request(
        "https://oauth2.googleapis.com/tokeninfo",
        headers={"Authorization": f"Bearer {token}"},
        method="GET",
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        info = json.loads(resp.read().decode("utf-8"))
    email = info.get("email")
    if not email:
        raise RuntimeError(
            "Unable to infer caller email from token; specify --grantee explicitly."
        )
    if email.endswith(".gserviceaccount.com"):
        return f"principal://iam.googleapis.com/projects/-/serviceAccounts/{email}"
    return f"principal://goog/subject/{email}"


# ---------------------------------------------------------------------------
# BigQuery REST v2 helpers (pure stdlib)
# ---------------------------------------------------------------------------


def _bq_ensure_dataset(
    project_id: str, dataset_id: str, location: str, labels: Dict[str, str]
) -> None:
    resp = _gcp_rest(
        "POST",
        f"{BQ_V2}/projects/{urllib.parse.quote(project_id, safe='')}/datasets",
        {
            "datasetReference": {"projectId": project_id, "datasetId": dataset_id},
            "location": location,
            "labels": labels,
        },
        allow_conflict=True,
    )
    status = "created" if resp is not None else "reusing"
    print(f"  [{status}] {project_id}.{dataset_id} (location={location})")


def _bq_query(
    project_id: str, sql: str, labels: Dict[str, str]
) -> List[Dict[str, Any]]:
    proj_q = urllib.parse.quote(project_id, safe="")
    resp = _gcp_rest(
        "POST",
        f"{BQ_V2}/projects/{proj_q}/queries",
        {
            "query": sql,
            "useLegacySql": False,
            "useQueryCache": False,
            "timeoutMs": 60000,
            "labels": labels,
        },
    ) or {}

    job_ref = resp.get("jobReference") or {}
    job_id = job_ref.get("jobId", "")
    job_loc = job_ref.get("location", "")

    while not resp.get("jobComplete", False):
        time.sleep(1.0)
        loc_qs = f"?location={urllib.parse.quote(job_loc)}" if job_loc else ""
        resp = _gcp_rest("GET", f"{BQ_V2}/projects/{proj_q}/queries/{job_id}{loc_qs}") or {}

    fields = [f["name"] for f in (resp.get("schema") or {}).get("fields", [])]
    rows: List[Dict[str, Any]] = []

    def _collect(page: Dict[str, Any]) -> None:
        for row in page.get("rows", []):
            vals = [cell.get("v") for cell in row.get("f", [])]
            rows.append(dict(zip(fields, vals)))

    _collect(resp)
    page_token = resp.get("pageToken") or ""
    while page_token and job_id:
        params = {"pageToken": page_token}
        if job_loc:
            params["location"] = job_loc
        qs = urllib.parse.urlencode(params)
        page = _gcp_rest("GET", f"{BQ_V2}/projects/{proj_q}/queries/{job_id}?{qs}") or {}
        _collect(page)
        page_token = page.get("pageToken") or ""

    return rows


def _bq_list_tables(project_id: str, dataset_id: str) -> List[Dict[str, Any]]:
    proj_q = urllib.parse.quote(project_id, safe="")
    ds_q = urllib.parse.quote(dataset_id, safe="")
    tables: List[Dict[str, Any]] = []
    page_token = ""
    while True:
        qs = f"maxResults=1000{f'&pageToken={urllib.parse.quote(page_token)}' if page_token else ''}"
        resp = _gcp_rest(
            "GET",
            f"{BQ_V2}/projects/{proj_q}/datasets/{ds_q}/tables?{qs}",
            allow_not_found=True,
        )
        if resp is None:
            return []
        tables.extend(resp.get("tables", []))
        page_token = resp.get("nextPageToken") or ""
        if not page_token:
            break
    return tables


def _bq_get_table(project_id: str, dataset_id: str, table_id: str) -> Dict[str, Any]:
    proj_q = urllib.parse.quote(project_id, safe="")
    ds_q = urllib.parse.quote(dataset_id, safe="")
    tbl_q = urllib.parse.quote(table_id, safe="")
    return _gcp_rest("GET", f"{BQ_V2}/projects/{proj_q}/datasets/{ds_q}/tables/{tbl_q}") or {}


def _bq_patch_table_schema(
    project_id: str, dataset_id: str, table_id: str, fields: List[Dict[str, Any]]
) -> None:
    proj_q = urllib.parse.quote(project_id, safe="")
    ds_q = urllib.parse.quote(dataset_id, safe="")
    tbl_q = urllib.parse.quote(table_id, safe="")
    _gcp_rest(
        "PATCH",
        f"{BQ_V2}/projects/{proj_q}/datasets/{ds_q}/tables/{tbl_q}",
        {"schema": {"fields": fields}},
    )


def _bq_delete_dataset(project_id: str, dataset_id: str) -> None:
    proj_q = urllib.parse.quote(project_id, safe="")
    ds_q = urllib.parse.quote(dataset_id, safe="")
    _gcp_rest(
        "DELETE",
        f"{BQ_V2}/projects/{proj_q}/datasets/{ds_q}?deleteContents=true",
        allow_not_found=True,
    )


# ---------------------------------------------------------------------------
# Resource Manager Tags & BigQuery Data Policy v2 helpers
# ---------------------------------------------------------------------------


def _ensure_dg_tag_key(project_number: str, short_name: str, description: str) -> str:
    url = f"{CRM_V3}/tagKeys?parent=projects/{project_number}&pageSize=300"
    existing = _gcp_rest("GET", url) or {}
    for item in existing.get("tagKeys", []):
        if item.get("shortName") == short_name:
            purpose = item.get("purpose")
            if purpose != "DATA_GOVERNANCE":
                raise RuntimeError(
                    f"Existing tagKey {item.get('namespacedName')} has purpose={purpose!r}, "
                    "expected 'DATA_GOVERNANCE'."
                )
            print(f"  [reusing] tagKey {item['namespacedName']} -> {item['name']}")
            return item["name"]

    op = _gcp_rest(
        "POST",
        f"{CRM_V3}/tagKeys",
        {
            "parent": f"projects/{project_number}",
            "shortName": short_name,
            "description": description,
            "purpose": "DATA_GOVERNANCE",
        },
    )
    created = _wait_crm_lro(op or {})
    print(f"  [created] tagKey {created.get('namespacedName')} -> {created['name']}")
    return created["name"]


def _ensure_dg_tag_value(parent_resource: str, short_name: str, description: str) -> str:
    url = (
        f"{CRM_V3}/tagValues?"
        f"parent={urllib.parse.quote(parent_resource, safe='/')}&pageSize=300"
    )
    existing = _gcp_rest("GET", url) or {}
    for item in existing.get("tagValues", []):
        if item.get("shortName") == short_name:
            print(f"  [reusing] tagValue {short_name} -> {item['name']}")
            return item["name"]

    op = _gcp_rest(
        "POST",
        f"{CRM_V3}/tagValues",
        {
            "parent": parent_resource,
            "shortName": short_name,
            "description": description,
        },
    )
    created = _wait_crm_lro(op or {})
    print(f"  [created] tagValue {short_name} -> {created['name']}")
    return created["name"]


def _ensure_v2_data_policy(
    project_id: str,
    location: str,
    policy_id: str,
    tag_key: str,
    tag_value: str,
    *,
    policy_type: str,
    grantee: str,
    predefined_expression: Optional[str] = None,
) -> None:
    loc_lower = location.lower()
    parent = f"projects/{project_id}/locations/{loc_lower}"
    full_name = f"{parent}/dataPolicies/{policy_id}"

    existing = _gcp_rest("GET", f"{DP_V2}/{full_name}", allow_not_found=True)
    if existing:
        print(f"  [reusing] Data Policy v2 {policy_id} ({existing.get('dataPolicyType')})")
        return

    body: Dict[str, Any] = {
        "dataPolicyId": policy_id,
        "dataPolicy": {
            "dataPolicyType": policy_type,
            "dataGovernanceTag": {"key": tag_key, "value": tag_value},
            "grantees": [grantee],
        },
    }
    if policy_type == "DATA_MASKING_POLICY":
        body["dataPolicy"]["dataMaskingPolicy"] = {
            "predefinedExpression": predefined_expression
        }

    _gcp_rest("POST", f"{DP_V2}/{parent}/dataPolicies", body)
    print(
        f"  [created] Data Policy v2 {policy_id} "
        f"({policy_type}{f'/{predefined_expression}' if predefined_expression else ''}) "
        f"on {tag_key}={tag_value}"
    )


def _list_v2_policies_for_key(
    project_id: str, location: str, tag_key_fqn: str
) -> List[Dict[str, Any]]:
    loc_lower = location.lower()
    parent = f"projects/{project_id}/locations/{loc_lower}"
    matched: List[Dict[str, Any]] = []
    page_token = ""
    while True:
        qs = f"pageSize=200{f'&pageToken={urllib.parse.quote(page_token)}' if page_token else ''}"
        resp = _gcp_rest("GET", f"{DP_V2}/{parent}/dataPolicies?{qs}") or {}
        for dp in resp.get("dataPolicies", []):
            tag = dp.get("dataGovernanceTag") or {}
            if tag.get("key") == tag_key_fqn:
                matched.append(dp)
        page_token = resp.get("nextPageToken") or ""
        if not page_token:
            break
    return matched


def _expected_tags(mode: str, class_key: str, domain_key: str) -> Dict[str, str]:
    """Return expected INFORMATION_SCHEMA tag assertions for `core` or `fusion`."""
    expected: Dict[str, str] = {
        "raw_customers.email": f"{class_key}=email",
        "raw_customers.work_email": f"{class_key}=email",
        "raw_customers.ssn": f"{class_key}=ssn",
        "raw_customers.loyalty_tier": f"{class_key}=public",
        "raw_customers.annual_income_usd": f"{domain_key}=finance",
        "raw_orders.amount_usd": f"{domain_key}=finance",
        "raw_orders.actor_email": f"{class_key}=email",
        "dim_customers.email": f"{class_key}=email",
        "dim_customers.ssn": f"{class_key}=ssn",
        "dim_customers.loyalty_tier": f"{class_key}=public",
        "dim_customers.annual_income_usd": f"{domain_key}=finance",
        "dim_customers.lifetime_spend_usd": f"{domain_key}=finance",
        "fct_customer_profiles.primary_email": f"{class_key}=email",
        "fct_customer_profiles.public_display_note": "",
        "dim_customers_contracted.email": f"{class_key}=email",
        "customers_snapshot.email": f"{class_key}=email",
        "customers_snapshot.ssn": f"{class_key}=ssn",
        "customers_snapshot.loyalty_tier": f"{class_key}=public",
    }
    if mode == "core":
        expected.update(
            {
                "fct_customer_profiles.profile.work_email": f"{class_key}=email",
                "fct_customer_profiles.profile.identity.ssn": f"{class_key}=ssn",
                "fct_customer_profiles.order_events.actor_email": f"{class_key}=email",
                "dim_customers_contracted.identity.ssn": f"{class_key}=ssn",
            }
        )
    else:
        expected.update(
            {
                "fct_customer_profiles.work_email": f"{class_key}=email",
                "fct_customer_profiles.ssn": f"{class_key}=ssn",
                "fct_customer_profiles.latest_actor_email": f"{class_key}=email",
                "fct_customer_profiles.profile_metadata": "",
                "dim_customers_contracted.ssn": f"{class_key}=ssn",
                "dim_customers_contracted.loyalty_tier": f"{class_key}=public",
                "customers_snapshot.annual_income_usd": f"{domain_key}=finance",
            }
        )
    return expected


# ---------------------------------------------------------------------------
# Subcommands
# ---------------------------------------------------------------------------


def cmd_setup(args: argparse.Namespace) -> int:
    project_id = _validate_project(args.project)
    dataset_id = _validate("dataset", args.dataset, _DATASET_RE)
    location = _validate("location", args.location, _LOCATION_RE)
    tag_project = _validate_project(args.tag_project or project_id)
    class_key_short = _validate("class tag key", args.class_key_name, _TAG_SHORT_RE)
    domain_key_short = _validate("domain tag key", args.domain_key_name, _TAG_SHORT_RE)
    policy_prefix = _validate("policy prefix", args.policy_prefix, _POLICY_PREFIX_RE)
    labels = _labels_for_mode(args.mode)

    print(f"Provisioning Data Governance Tag keys under project: {tag_project}")
    tag_project_number = _resolve_project_number(tag_project)

    class_key_res = _ensure_dg_tag_key(
        tag_project_number,
        class_key_short,
        f"dbt ({args.mode}) BigQuery Data Governance Tags example - classification key",
    )
    v_pii = _ensure_dg_tag_value(class_key_res, "pii", "PII root classification")
    _ensure_dg_tag_value(v_pii, "email", "Email PII leaf value (under pii)")
    _ensure_dg_tag_value(v_pii, "ssn", "SSN PII leaf value (under pii)")
    _ensure_dg_tag_value(class_key_res, "public", "Public non-sensitive leaf value")

    domain_key_res = _ensure_dg_tag_key(
        tag_project_number,
        domain_key_short,
        f"dbt ({args.mode}) BigQuery Data Governance Tags example - domain key",
    )
    _ensure_dg_tag_value(domain_key_res, "finance", "Finance domain leaf value")

    print(f"\nEnsuring BigQuery dataset: {project_id}.{dataset_id} (location={location})")
    _bq_ensure_dataset(project_id, dataset_id, location, labels)

    class_key_fqn = f"{tag_project}/{class_key_short}"
    created_policies = False

    if args.with_masking_policies or args.with_raw_access_policies:
        grantee = args.grantee or _get_active_iam_v3_principal()
        _validate("grantee principal", grantee, _PRINCIPAL_RE)
        created_policies = True

        if args.with_masking_policies:
            print(f"\nBinding BigQuery Data Policy v2 masking rules (grantee={grantee})")
            _ensure_v2_data_policy(
                project_id,
                location,
                f"{policy_prefix}_email_mask",
                class_key_fqn,
                "email",
                policy_type="DATA_MASKING_POLICY",
                predefined_expression="EMAIL_MASK",
                grantee=grantee,
            )
            _ensure_v2_data_policy(
                project_id,
                location,
                f"{policy_prefix}_ssn_sha256",
                class_key_fqn,
                "ssn",
                policy_type="DATA_MASKING_POLICY",
                predefined_expression="SHA256",
                grantee=grantee,
            )
            _ensure_v2_data_policy(
                project_id,
                location,
                f"{policy_prefix}_public_raw",
                class_key_fqn,
                "public",
                policy_type="RAW_DATA_ACCESS_POLICY",
                grantee=grantee,
            )

        if args.with_raw_access_policies:
            print(f"\nBinding BigQuery Data Policy v2 raw access rules (grantee={grantee})")
            for tag_val in ("email", "ssn", "public"):
                _ensure_v2_data_policy(
                    project_id,
                    location,
                    f"{policy_prefix}_{tag_val}_raw",
                    class_key_fqn,
                    tag_val,
                    policy_type="RAW_DATA_ACCESS_POLICY",
                    grantee=grantee,
                )
    else:
        existing_policies = _list_v2_policies_for_key(project_id, location, class_key_fqn)
        if existing_policies:
            covered_vals = sorted(
                {
                    (dp.get("dataGovernanceTag") or {}).get("value", "")
                    for dp in existing_policies
                }
            )
            print(
                f"\n[WARNING] Found {len(existing_policies)} existing V2 Data Policy rule(s) "
                f"on {class_key_fqn} in {location} (values: {', '.join(covered_vals)})."
            )
            print(
                "  Because this Tag Key already has V2 Data Policies in this region, BigQuery\n"
                "  enforces default-deny across ALL its tag values (including `public`).\n"
                "  Run `make setup-gcp-raw-access` to grant your dbt runner leaf-level raw access."
            )

    if created_policies:
        print(
            "\nNote: Newly created BigQuery Data Policy v2 rules are eventually consistent\n"
            "and may take 1-5 minutes to propagate to BigQuery query evaluation."
        )

    print("\nSetup complete. Next steps:")
    print(f"  export GCP_PROJECT_ID={project_id}")
    print(f"  export BQ_DATASET={dataset_id}")
    print(f"  export BQ_LOCATION={location}")
    if tag_project != project_id:
        print(f"  export DGT_PARENT_ID={tag_project}")
    print(f"  make all verify-gcp PROJECT={project_id} DATASET={dataset_id}")
    return 0


def cmd_verify(args: argparse.Namespace) -> int:
    project_id = _validate_project(args.project)
    dataset_id = _validate("dataset", args.dataset, _DATASET_RE)
    tag_parent = args.tag_parent or project_id
    class_key = f"{tag_parent}/{_validate('class tag key', args.class_key_name, _TAG_SHORT_RE)}"
    domain_key = f"{tag_parent}/{_validate('domain tag key', args.domain_key_name, _TAG_SHORT_RE)}"
    labels = _labels_for_mode(args.mode)

    sql = f"""
    SELECT
      table_name,
      field_path,
      data_type,
      ARRAY_TO_STRING(
        ARRAY(
          SELECT CONCAT(t.key, '=', t.value)
          FROM UNNEST(data_governance_tags) AS t
          ORDER BY t.key
        ),
        ', '
      ) AS data_governance_tags
    FROM `{project_id}`.`{dataset_id}`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
    ORDER BY table_name, field_path
    """
    rows = _bq_query(project_id, sql, labels)

    if not rows:
        print(f"No columns found in {project_id}.{dataset_id}. Run dbt seed/run/snapshot first.")
        return 1

    observed: Dict[str, str] = {}
    print(f"Attached Data Governance Tags in {project_id}.{dataset_id} (mode={args.mode}):\n")
    print(f"{'TABLE.FIELD_PATH':<48} {'TYPE':<12} {'DATA_GOVERNANCE_TAGS'}")
    print("-" * 108)
    for r in rows:
        fq_col = f"{r['table_name']}.{r['field_path']}"
        tags = r.get("data_governance_tags") or ""
        dtype = r.get("data_type") or ""
        observed[fq_col] = tags
        if tags or args.all_columns:
            print(f"{fq_col:<48} {dtype[:11]:<12} {tags or '-'}")

    expected = _expected_tags(args.mode, class_key, domain_key)
    mismatches = [
        (col, exp_val, observed.get(col))
        for col, exp_val in expected.items()
        if observed.get(col) != exp_val
    ]

    print()
    if mismatches:
        print("VERIFICATION FAILED — tag mismatches found:")
        for col, exp_val, actual in mismatches:
            print(f"  - {col}: expected={exp_val!r}, actual={actual!r}")
        return 1

    print(
        f"VERIFICATION PASSED ({args.mode}) — all {len(expected)} expected "
        "column governance tag assertions matched."
    )
    return 0


def _clear_field_tags_recursive(fields: List[Dict[str, Any]]) -> bool:
    changed = False
    for field in fields:
        if field.get("fields"):
            if _clear_field_tags_recursive(field["fields"]):
                changed = True
        else:
            if field.get("dataGovernanceTagsInfo", {}).get("dataGovernanceTags"):
                field["dataGovernanceTagsInfo"] = {"dataGovernanceTags": {}}
                changed = True
            if field.get("policyTags", {}).get("names"):
                field["policyTags"] = {"names": []}
                changed = True
    return changed


def cmd_teardown(args: argparse.Namespace) -> int:
    if not args.yes:
        print(
            "Refusing destructive teardown without --yes. "
            "Re-run with --yes to detach tags, drop the dataset, and remove temporary policies."
        )
        return 2

    project_id = _validate_project(args.project)
    dataset_id = _validate("dataset", args.dataset, _DATASET_RE)
    location = _validate("location", args.location, _LOCATION_RE)
    policy_prefix = _validate("policy prefix", args.policy_prefix, _POLICY_PREFIX_RE)
    dataset_fqn = f"{project_id}.{dataset_id}"

    for tbl_item in _bq_list_tables(project_id, dataset_id):
        if tbl_item.get("type") == "TABLE":
            table_id = (tbl_item.get("tableReference") or {}).get("tableId")
            if not table_id:
                continue
            full_tbl = _bq_get_table(project_id, dataset_id, table_id)
            raw_fields = copy.deepcopy((full_tbl.get("schema") or {}).get("fields", []))
            if _clear_field_tags_recursive(raw_fields):
                _bq_patch_table_schema(project_id, dataset_id, table_id, raw_fields)
                print(f"  [detached tags] {dataset_fqn}.{table_id}")

    _bq_delete_dataset(project_id, dataset_id)
    print(f"  [deleted dataset] {dataset_fqn}")

    loc_lower = location.lower()
    parent = f"projects/{project_id}/locations/{loc_lower}"
    for suffix in ("email_mask", "ssn_sha256", "email_raw", "ssn_raw", "public_raw", "pii_raw"):
        pol_name = f"{parent}/dataPolicies/{policy_prefix}_{suffix}"
        resp = _gcp_rest("DELETE", f"{DP_V2}/{pol_name}", allow_not_found=True)
        if resp is not None:
            print(f"  [deleted policy] {pol_name}")

    print("\nTeardown complete. (Reusable DATA_GOVERNANCE Tag Keys were preserved.)")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Zero-dependency GCP setup/verify/teardown helper for dbt Core 1.x & dbt v2 / Fusion DGT examples."
    )
    parser.add_argument(
        "--mode",
        choices=("core", "fusion"),
        default="core",
        help="Target example flavor controlling verification assertions & labels (core or fusion).",
    )
    parser.add_argument(
        "--project",
        default=os.environ.get("GCP_PROJECT_ID", ""),
        help="Target BigQuery GCP project ID (default: $GCP_PROJECT_ID).",
    )
    parser.add_argument(
        "--dataset",
        default=os.environ.get("BQ_DATASET", "dbt_dgt_example"),
        help="Target BigQuery dataset name (default: $BQ_DATASET or dbt_dgt_example).",
    )
    parser.add_argument(
        "--location",
        default=os.environ.get("BQ_LOCATION", "US"),
        help="BigQuery dataset & Data Policy location (default: $BQ_LOCATION or US).",
    )
    parser.add_argument(
        "--class-key-name",
        default=os.environ.get("DGT_CLASS_KEY_NAME", "dbt_dgt_e2e_class"),
        help="Classification TagKey shortName (default: $DGT_CLASS_KEY_NAME or dbt_dgt_e2e_class).",
    )
    parser.add_argument(
        "--domain-key-name",
        default=os.environ.get("DGT_DOMAIN_KEY_NAME", "dbt_dgt_e2e_domain"),
        help="Domain TagKey shortName (default: $DGT_DOMAIN_KEY_NAME or dbt_dgt_e2e_domain).",
    )
    parser.add_argument(
        "--policy-prefix",
        default="dbt_dgt_example",
        help="Prefix for optional BigQuery Data Policy API v2 rule IDs.",
    )

    sub = parser.add_subparsers(dest="command", required=True)

    p_setup = sub.add_parser("setup", help="Create tag keys/values, dataset, and optional V2 policies.")
    p_setup.add_argument(
        "--tag-project",
        default=os.environ.get("DGT_PARENT_ID", ""),
        help="Optional separate GCP project ID that owns the TagKeys (defaults to --project).",
    )
    p_setup.add_argument(
        "--with-masking-policies",
        action="store_true",
        help="Also bind V2 EMAIL_MASK (email), SHA256 (ssn), and RAW_DATA_ACCESS_POLICY (public).",
    )
    p_setup.add_argument(
        "--with-raw-access-policies",
        action="store_true",
        help="Also bind leaf-level V2 RAW_DATA_ACCESS_POLICY rules on email, ssn, and public for the dbt runner.",
    )
    p_setup.add_argument(
        "--grantee",
        default="",
        help="IAM v3 principal URI for V2 policies (defaults to active ADC principal).",
    )
    p_setup.set_defaults(func=cmd_setup)

    p_verify = sub.add_parser("verify", help="Verify attached tags via INFORMATION_SCHEMA.")
    p_verify.add_argument(
        "--tag-parent",
        default=os.environ.get("DGT_PARENT_ID", ""),
        help="Expected TagKey parent ID (project ID or org ID; defaults to --project).",
    )
    p_verify.add_argument(
        "--all-columns",
        action="store_true",
        help="Print untagged columns as well as tagged columns.",
    )
    p_verify.set_defaults(func=cmd_verify)

    p_teardown = sub.add_parser("teardown", help="Detach tags and delete example dataset & V2 policies.")
    p_teardown.add_argument(
        "--yes",
        action="store_true",
        help="Confirm destructive deletion of <project>.<dataset> and temporary V2 policies.",
    )
    p_teardown.set_defaults(func=cmd_teardown)

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    try:
        return args.func(args)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())

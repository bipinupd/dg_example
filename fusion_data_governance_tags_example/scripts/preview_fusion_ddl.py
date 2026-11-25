#!/usr/bin/env python3
"""Render & verify exact dbt v2 / Fusion BigQuery ALTER TABLE DDL offline.

Loads the real `bigquery__persist_docs` and
`bigquery__get_alter_column_data_governance_tags_sql` macros directly from
`dbt/dbt/crates/dbt-loader/src/dbt_macro_assets/dbt-bigquery/macros/adapters.sql`
and evaluates them against this project's compiled `target/manifest.json` so you
can inspect and validate every Fusion DDL statement, ordered rollback sequence,
and fast-fail compiler guard without executing any BigQuery writes.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any, Dict, List

import jinja2


class _CompilerError(RuntimeError):
    pass


class _ExceptionsStub:
    def raise_compiler_error(self, msg: str) -> None:
        raise _CompilerError(msg)


class _ColumnStub:
    def __init__(self, flat_names: List[str]):
        self._flat_names = flat_names

    def flatten(self) -> List["_FlatCol"]:
        return [_FlatCol(n) for n in self._flat_names]


class _FlatCol:
    def __init__(self, name: str):
        self.name = name


class _RelationStub:
    def __init__(self, rtype: str, database: str, schema: str, identifier: str):
        self.type = rtype
        self.database = database
        self.schema = schema
        self.identifier = identifier

    def __str__(self) -> str:
        return f"`{self.database}`.`{self.schema}`.`{self.identifier}`"


class _ConfigStub:
    def persist_relation_docs(self) -> bool:
        return False

    def persist_column_docs(self) -> bool:
        return True


def _extract_macro(src: str, macro_name: str) -> str:
    marker = f"{{% macro {macro_name}"
    start = src.index(marker)
    end_idx = src.index("endmacro %}", start) + len("endmacro %}")
    return src[start:end_idx]


def _build_env(adapters_sql_path: Path) -> jinja2.Environment:
    raw_sql = adapters_sql_path.read_text(encoding="utf-8")
    m_persist = _extract_macro(raw_sql, "bigquery__persist_docs")
    m_get_sql = _extract_macro(raw_sql, "bigquery__get_alter_column_data_governance_tags_sql")
    m_alter_comment = _extract_macro(raw_sql, "bigquery__alter_column_comment")

    env = jinja2.Environment(extensions=["jinja2.ext.do"])
    env.globals["return"] = lambda val="": val
    env.globals["exceptions"] = _ExceptionsStub()
    env.globals["_macros_src"] = "\n".join([m_alter_comment, m_get_sql, m_persist])
    return env


def _render_ddl_for_node(
    env: jinja2.Environment,
    relation: _RelationStub,
    columns: Dict[str, Any],
    record_columns: List[str] | None = None,
) -> str:
    class _Adapter:
        def quote(self, name: str) -> str:
            return f"`{name}`"

    tmpl = env.from_string(
        env.globals["_macros_src"]
        + "\n{{ bigquery__get_alter_column_data_governance_tags_sql(relation, column_dict, record_columns) }}"
    )
    return tmpl.render(
        adapter=_Adapter(),
        relation=relation,
        column_dict=columns,
        record_columns=record_columns,
    ).strip()


def _simulate_persist_docs_order(
    env: jinja2.Environment,
    relation: _RelationStub,
    columns: Dict[str, Any],
    flat_schema_paths: List[str],
) -> List[str]:
    events: List[str] = []

    class _Adapter:
        def quote(self, name: str) -> str:
            return f"`{name}`"

        def get_columns_in_relation(self, _rel: Any) -> List[_ColumnStub]:
            return [_ColumnStub(flat_schema_paths)]

        def update_columns(self, _rel: Any, _cols: Dict[str, Any]) -> None:
            events.append("ADBC adapter.update_columns(descriptions + legacy policy_tags)")

    def _run_query(sql: str) -> None:
        events.append("SQL run_query:\n" + sql.strip())

    def _validate_doc_columns(_rel: Any, model_cols: Dict[str, Any], valid_names: List[str]) -> Dict[str, Any]:
        valid_lower = {v.lower() for v in valid_names}
        return {k: v for k, v in model_cols.items() if k.lower() in valid_lower}

    def _alter_column_comment(rel: Any, cols: Dict[str, Any]) -> None:
        events.append("ADBC adapter.update_columns(descriptions + legacy policy_tags)")

    tmpl = env.from_string(
        env.globals["_macros_src"]
        + "\n{% do bigquery__persist_docs(relation, model, false, true) %}"
    )
    tmpl.render(
        adapter=_Adapter(),
        config=_ConfigStub(),
        relation=relation,
        model={"columns": columns, "description": ""},
        dbt_version="2.0.0",
        run_query=_run_query,
        validate_doc_columns=_validate_doc_columns,
        alter_column_comment=_alter_column_comment,
    )
    return events


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Preview & validate exact dbt v2 / Fusion BigQuery DDL from adapters.sql."
    )
    parser.add_argument(
        "--manifest",
        default="target/manifest.json",
        help="Path to compiled manifest.json (default: target/manifest.json).",
    )
    parser.add_argument(
        "--adapters-sql",
        default="../../dbt/crates/dbt-loader/src/dbt_macro_assets/dbt-bigquery/macros/adapters.sql",
        help="Path to Fusion's dbt-bigquery adapters.sql macro file.",
    )
    args = parser.parse_args()

    manifest_path = Path(args.manifest)
    adapters_sql_path = Path(args.adapters_sql)
    if not manifest_path.exists():
        print(f"ERROR: {manifest_path} not found. Run `make compile` first.", file=sys.stderr)
        return 1
    if not adapters_sql_path.exists():
        print(f"ERROR: Fusion adapters.sql not found at {adapters_sql_path}.", file=sys.stderr)
        return 1

    env = _build_env(adapters_sql_path)
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))

    print("==========================================================================")
    print("1. GENERATED dbt v2 / FUSION DDL FOR PROJECT RESOURCES")
    print("==========================================================================")

    ddl_count = 0
    for _uid, node in sorted(manifest["nodes"].items()):
        rtype = node["resource_type"]
        if rtype not in ("model", "seed", "snapshot"):
            continue
        mat = node["config"].get("materialized", "")
        rel_type = "view" if mat == "view" else "table"
        rel = _RelationStub(rel_type, node["database"], node["schema"], node["alias"])
        cols = node.get("columns", {})
        rec_cols = ["profile_metadata"] if node["name"] == "fct_customer_profiles" else []

        ddl = _render_ddl_for_node(env, rel, cols, record_columns=rec_cols)
        if ddl:
            ddl_count += 1
            print(f"\n-- [{rtype}:{mat}] {node['name']} --")
            print(ddl + ";")
        else:
            print(f"\n-- [{rtype}:{mat}] {node['name']} -- (no DGT DDL emitted; descriptions only)")

    assert ddl_count == 6, f"Expected DDL for 6 table/seed/snapshot resources, got {ddl_count}"

    print("\n==========================================================================")
    print("2. SIMULATED FUSION ORDERED ROLLBACK (DGT -> LEGACY policy_tags)")
    print("==========================================================================")
    sample_node = next(
        n
        for n in manifest["nodes"].values()
        if n.get("resource_type") == "model" and n.get("name") == "dim_customers"
    )
    sample_db = sample_node["database"]
    sample_schema = sample_node["schema"]
    sample_key = next(iter(sample_node["columns"]["email"]["data_governance_tags"].keys()))
    rollback_rel = _RelationStub("table", sample_db, sample_schema, "dim_customers")
    rollback_events = _simulate_persist_docs_order(
        env,
        rollback_rel,
        columns={
            "ssn": {
                "data_governance_tags": {},
                "policy_tags": [
                    f"projects/{sample_db}/locations/us/taxonomies/123/policyTags/456"
                ],
            },
            "email": {
                "data_governance_tags": {sample_key: "email"},
            },
        },
        flat_schema_paths=["ssn", "email"],
    )
    for idx, step in enumerate(rollback_events, 1):
        print(f"\nStep {idx}: {step}")
    assert len(rollback_events) == 3
    assert "data_governance_tags=[]" in rollback_events[0]
    assert "adapter.update_columns" in rollback_events[1]
    assert f'("{sample_key}", "email")' in rollback_events[2]

    print("\n==========================================================================")
    print("3. FUSION FAST-FAIL VALIDATION GUARDS")
    print("==========================================================================")
    table_rel = _RelationStub("table", sample_db, sample_schema, "guard_demo")
    view_rel = _RelationStub("view", sample_db, sample_schema, "guard_view")
    guards = [
        ("VIEW with DGT", view_rel, {"email": {"data_governance_tags": {sample_key: "email"}}}, []),
        ("STRUCT parent with DGT", table_rel, {"profile_metadata": {"data_governance_tags": {sample_key: "public"}}}, ["profile_metadata"]),
        ("Dotted nested STRUCT path", table_rel, {"profile_metadata.country_code": {"data_governance_tags": {sample_key: "public"}}}, ["profile_metadata"]),
        ("Both policy_tags & DGT", table_rel, {"email": {"policy_tags": ["projects/p/locations/us/taxonomies/1/policyTags/2"], "data_governance_tags": {sample_key: "email"}}}, []),
        ("Hierarchical slash value", table_rel, {"email": {"data_governance_tags": {sample_key: "pii/email"}}}, []),
        ("Invalid key (no slash)", table_rel, {"email": {"data_governance_tags": {"missing_slash": "email"}}}, []),
    ]
    for label, rel, cols, recs in guards:
        try:
            _render_ddl_for_node(env, rel, cols, record_columns=recs)
            raise AssertionError(f"Expected Fusion guard failure for: {label}")
        except _CompilerError as exc:
            print(f"  [BLOCKED - {label}] {exc}")

    print("\nALL FUSION DDL, ROLLBACK & GUARD CHECKS PASSED!")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

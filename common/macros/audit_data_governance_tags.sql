{% macro audit_data_governance_tags(table_name=none) %}
{#
  Inspect attached BigQuery Data Governance Tags (and legacy policy tags) in the
  active target project & dataset via INFORMATION_SCHEMA.COLUMN_FIELD_PATHS.

  Usage:
    dbt run-operation audit_data_governance_tags
    dbt run-operation audit_data_governance_tags --args '{"table_name": "dim_customers"}'
#}
{% if not execute %}
    {% do return(none) %}
{% endif %}

{% set target_project = target.database %}
{% set target_dataset = target.schema %}

{% set sql %}
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
    ) AS data_governance_tags,
    ARRAY_TO_STRING(policy_tags, ', ') AS legacy_policy_tags,
    COALESCE(description, '') AS description
FROM `{{ target_project }}`.`{{ target_dataset }}`.INFORMATION_SCHEMA.COLUMN_FIELD_PATHS
{% if table_name is not none %}
WHERE table_name = '{{ table_name | replace("'", "''") }}'
{% endif %}
ORDER BY table_name, field_path
{% endset %}

{% set results = run_query(sql) %}

{% do log("================================================================================", info=true) %}
{% do log("Data Governance Tag Audit (dbt " ~ dbt_version ~ "): " ~ target_project ~ "." ~ target_dataset, info=true) %}
{% do log("================================================================================", info=true) %}

{% if results | length == 0 %}
    {% do log("No columns found. Run `dbt seed`, `dbt run`, and `dbt snapshot` first.", info=true) %}
{% else %}
    {% set ns = namespace(tagged_count=0) %}
    {% for row in results %}
        {% set dgt = row['data_governance_tags'] or '' %}
        {% set pt = row['legacy_policy_tags'] or '' %}
        {% if dgt != '' %}
            {% set ns.tagged_count = ns.tagged_count + 1 %}
        {% endif %}
        {% do log(
            row['table_name'] ~ "." ~ row['field_path']
            ~ " (" ~ row['data_type'] ~ ")"
            ~ " | DGT: " ~ (dgt if dgt != '' else '-')
            ~ (" | Legacy PT: " ~ pt if pt != '' else ''),
            info=true
        ) %}
    {% endfor %}
    {% do log("--------------------------------------------------------------------------------", info=true) %}
    {% do log("Total columns inspected: " ~ (results | length) ~ " | Tagged with DGT: " ~ ns.tagged_count, info=true) %}
{% endif %}
{% endmacro %}

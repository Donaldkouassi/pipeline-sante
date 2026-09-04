{#
  Par défaut, dbt PRÉFIXE le schéma cible au schéma personnalisé :
  target.schema = "marts" + schema: staging  ->  "marts_staging".
  Cette macro dit à dbt d'utiliser le nom tel quel.
  C'est le premier piège de tout projet dbt.
#}
{% macro generate_schema_name(custom_schema_name, node) -%}
    {%- if custom_schema_name is none -%}
        {{ target.schema }}
    {%- else -%}
        {{ custom_schema_name | trim }}
    {%- endif -%}
{%- endmacro %}

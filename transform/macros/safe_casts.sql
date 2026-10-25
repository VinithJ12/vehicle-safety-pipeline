{% macro safe_int(col) -%}
    case when pg_input_is_valid({{ col }}, 'integer') then {{ col }}::integer end
{%- endmacro %}

{% macro safe_date(col) -%}
    case when pg_input_is_valid({{ col }}, 'date') then {{ col }}::date end
{%- endmacro %}
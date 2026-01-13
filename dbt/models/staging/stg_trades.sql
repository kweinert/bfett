{{ config(
    materialized='incremental',
    unique_key='isin||trade_time||price||currency||size'
) }}

{% if execute %}
{# Ermittle max_date #}
    {% if is_incremental() %}
        {% set max_date_result = run_query("SELECT COALESCE(MAX(trade_time)::DATE, '1900-01-01') AS max_date FROM " ~ this) %}
        {% set max_date_value = max_date_result.rows[0][0]|string if max_date_result else '1900-01-01' %}
    {% else %}
        {% set max_date_value = '1900-01-01' %}
    {% endif %}
    {# {{ log("max_date is: " ~ max_date_value, info=True) }} #}

    {# Liste der Dateien abrufen und filtern #}
    {% set files_query %}
        SELECT file AS filename FROM glob('/app/data/lsx_trades/*.csv.gz')
    {% endset %}
    {% set files_result = run_query(files_query) %}
    {# {{ log("files_result contains: " ~ files_result|join(", "), info=True) }} #}

    {% set files_to_process = [] %}
    {% for row in files_result %}
        {% set filename = row['filename'] %}
        {% set file_date = filename|replace('/app/data/lsx_trades/lsx_trades_', '')|replace('.csv.gz', '') %}
        {% if file_date > max_date_value %}
            {% do files_to_process.append(filename) %}
        {% endif %}
    {% endfor %}
    {# {{ log("files_to_process contains: " ~ files_to_process|join(", "), info=True) }} #}
{% endif %}

WITH max_date AS (
    SELECT '{{ max_date_value }}'::DATE AS max_date
),

new_trades AS (
    {% if files_to_process %}
        SELECT 
            isin,
            CAST(tradeTime AS TIMESTAMP) AS trade_time,
            price,
            currency,
            size
        FROM read_csv_auto(
            {{ files_to_process|tojson }},
            delim = ';',              -- Semikolon als Trennzeichen
			decimal_separator = ',',  -- Komma als Dezimalpunkt
			header = true,            -- Erwartet Kopfzeile
			timestampformat = '%Y-%m-%dT%H:%M:%S.%fZ'
        )
        {% if is_incremental() %}
            WHERE trade_time > (SELECT max_date FROM max_date)
        {% endif %}
    {% else %}
        -- Keine Dateien zu verarbeiten
        SELECT 
            CAST(NULL AS VARCHAR) AS isin,
            CAST(NULL AS TIMESTAMP) AS trade_time,
            CAST(NULL AS DOUBLE) AS price,
            CAST(NULL AS VARCHAR) AS currency,
            CAST(NULL AS DOUBLE) AS size
        WHERE 1=0
    {% endif %}
)

SELECT * FROM new_trades
{% if is_incremental() and not files_to_process %}
    -- Bei inkrementellem Lauf ohne neue Dateien: leerer Datensatz
    UNION ALL
    SELECT * FROM {{ this }} WHERE 1=0
{% endif %}



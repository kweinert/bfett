{{ config(materialized='table') }}

/* Ich habe eine Tabelle cash in dbt wie folgt:

"date","cash","portfolio"
"2025-04-07",-55.36,"elvis"
"2025-04-10",0,"elvis"
"2024-04-03",1,"nert"
"2024-04-04",15001,"nert"
"2024-04-08",498,"nert"

Ich nutze duckdb als Backend.

Ich möchte ein neues Modell cash_weekly entwickeln, mit den Spalten portfolio, cash, calendar_week.

calendar_week soll im Format YYYY-WW sein und alle Wochen nach dem ISO 8601-Standard vom ältesten Datum in der Tabelle bis heute (d.h. bis zum Tag der Abfrage) abdecken.

cash soll der letzte verfügbare Wert bis zum Ende der Kalenderwoche sein. Dabei kann es auftreten, dass es in einer Woche keine Einträge gibt.

Generiere das Modell. Benutze CTEs um den Code verständlich zu halten.

*/

-- Generiere alle Kalenderwochen vom min_date bis heute
WITH week_dates AS (
    SELECT 
       UNNEST(generate_series(MIN(date), CURRENT_DATE, interval '1 week')) as week_date
    FROM {{ ref('cash') }} 
),

-- calender_week, Sunday of that week.
all_weeks AS (
    SELECT
        CONCAT(
          EXTRACT(YEAR FROM week_date), 
          '-', 
          LPAD(EXTRACT(WEEK FROM week_date)::TEXT, 2, '0')
        ) AS calendar_week,
        (date_trunc('week', week_date) + interval '6 days')::DATE AS week_date
    FROM week_dates
),

-- last cash entry per Portfolio und Woche. Might be missing for some weeks.
last_cash AS (
    SELECT DISTINCT ON (c.portfolio, aw.calendar_week)
        c.portfolio,
        aw.calendar_week,
        c.cash
    FROM all_weeks AS aw
    LEFT JOIN {{ ref('cash') }}  AS c
        ON c.date <= aw.week_date
        AND c.date > aw.week_date - interval '7 days'
    ORDER BY c.portfolio, aw.calendar_week, c.date DESC
),

-- fill missings with the last known value (forward fill) 
-- or 0 if there is no known previous value.
filled_cash AS (
    SELECT
        p.portfolio,
        ws.calendar_week,
        COALESCE(
            lc.cash,
            LAST_VALUE(lc.cash IGNORE NULLS) OVER (
                PARTITION BY p.portfolio 
                ORDER BY ws.week_date
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ),
            0
        ) as cash
    FROM all_weeks ws
    CROSS JOIN (SELECT DISTINCT portfolio FROM {{ ref('cash') }} ) p
    LEFT JOIN last_cash lc
        ON lc.portfolio = p.portfolio
        AND lc.calendar_week = ws.calendar_week
)

SELECT 
    portfolio,
    calendar_week,
    cash
FROM filled_cash
ORDER BY portfolio, calendar_week

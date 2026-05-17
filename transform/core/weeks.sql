SELECT
    CONCAT(EXTRACT(YEAR FROM week_start), '-',
           LPAD(EXTRACT(WEEK FROM week_start)::TEXT, 2, '0')) AS calendar_week,
    week_start::DATE AS from_date,
    (week_start + INTERVAL '6 days')::DATE AS until_date
FROM (
    SELECT UNNEST(generate_series(
        (SELECT MIN(date) FROM staging.transactions),
        CURRENT_DATE,
        INTERVAL '1 week'
    )) AS week_start
)
-- #NO_NULLS calendar_week, from_date, until_date
-- #UNIQUE calendar_week

WITH last_cash AS (
    SELECT DISTINCT ON (c.portfolio, w.calendar_week)
        c.portfolio,
        w.calendar_week,
        c.cash
    FROM core.weeks w
    LEFT JOIN staging.cash c
        ON c.date <= w.until_date
        AND c.date > w.from_date
    ORDER BY c.portfolio, w.calendar_week, c.date DESC
),
filled_cash AS (
    SELECT
        p.portfolio,
        w.calendar_week,
        COALESCE(
            lc.cash,
            LAST_VALUE(lc.cash IGNORE NULLS) OVER (
                PARTITION BY p.portfolio
                ORDER BY w.from_date
                ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ),
            0
        ) as cash
    FROM core.weeks w
    CROSS JOIN (SELECT DISTINCT portfolio FROM staging.cash) p
    LEFT JOIN last_cash lc
        ON lc.portfolio = p.portfolio
        AND lc.calendar_week = w.calendar_week
)
SELECT
    portfolio,
    calendar_week,
    cash
FROM filled_cash
ORDER BY portfolio, calendar_week
-- #NO_NULLS portfolio, calendar_week, cash

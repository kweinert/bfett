WITH positions_with_weeks AS (
    SELECT
        ap.isin,
        i.name,
        ap.buy_date,
        ap.size,
        ap.buy_price,
        i.category,
        ap.portfolio,
        CONCAT(EXTRACT(YEAR FROM ap.buy_date), '-', LPAD(EXTRACT(WEEK FROM ap.buy_date)::TEXT, 2, '0')) AS buy_week
    FROM staging.active_positions ap
    LEFT JOIN core.instruments i ON i.isin = ap.isin
),
calendar_weeks AS (
    SELECT calendar_week FROM core.weeks
),
portfolios AS (
    SELECT DISTINCT portfolio FROM positions_with_weeks
),
isins AS (
    SELECT DISTINCT isin FROM positions_with_weeks
),
week_portfolio_isin AS (
    SELECT
        cw.calendar_week,
        p.portfolio,
        i.isin
    FROM calendar_weeks cw
    CROSS JOIN portfolios p
    CROSS JOIN isins i
),
positions AS (
    SELECT
        isin,
        portfolio,
        buy_week,
        name,
        category,
        SUM(size) AS size,
        SUM(size * buy_price) AS buy_in,
        AVG(buy_price) AS buy_price
    FROM positions_with_weeks
    GROUP BY isin, portfolio, buy_week, name, category
),
trades AS (
    SELECT
        isin,
        calendar_week,
        close,
        previous_close
    FROM core.ohlc_weekly
),
filtered_positions AS (
    SELECT
        wpi.calendar_week,
        wpi.portfolio,
        wpi.isin,
        p.name,
        p.category,
        p.size,
        p.buy_in,
        p.buy_price,
        p.buy_week
    FROM week_portfolio_isin wpi
    LEFT JOIN positions p
        ON wpi.isin = p.isin
        AND wpi.portfolio = p.portfolio
        AND p.buy_week <= wpi.calendar_week
),
final AS (
    SELECT
        fp.isin,
        fp.name,
        fp.category,
        fp.portfolio,
        fp.calendar_week,
        fp.size,
        fp.buy_in,
        COALESCE(t.close, fp.buy_price) * fp.size AS close_value,
        COALESCE(t.previous_close, fp.buy_price) * fp.size AS previous_close_value
    FROM filtered_positions fp
    LEFT JOIN trades t
        ON fp.isin = t.isin
        AND fp.calendar_week = t.calendar_week
    WHERE fp.size IS NOT NULL
)
SELECT
    isin,
    name,
    category,
    portfolio,
    calendar_week,
    size,
    buy_in,
    close_value,
    previous_close_value
FROM final
ORDER BY isin, portfolio, calendar_week
-- #NO_NULLS isin, name, category, portfolio, calendar_week, size, buy_in, close_value, previous_close_value

WITH positions_with_weeks AS (
  SELECT
        ap.isin,
        COALESCE(info.name, ap.isin) AS name,
        ap.buy_date,
        ap.size,
        ap.buy_price,
        COALESCE(idea.category, '(ohne Idee)') AS category,
        ap.portfolio,
        CONCAT(EXTRACT(YEAR FROM ap.buy_date), '-', LPAD(EXTRACT(WEEK FROM ap.buy_date)::TEXT, 2, '0')) AS buy_week
    FROM {{ ref('active_positions') }} AS ap
    LEFT JOIN {{ ref('isin_info') }} AS info ON info.isin=ap.isin
    LEFT JOIN {{ ref('invest_ideas') }} AS idea ON idea.isin=ap.isin
),
  
calendar_weeks AS (
    -- Generiere alle relevanten Kalenderwochen (z.B. aus int_trades_weekly oder positions_with_weeks)
    SELECT DISTINCT calendar_week
    FROM {{ ref('int_trades_weekly') }}
    UNION
    SELECT DISTINCT buy_week AS calendar_week
    FROM positions_with_weeks
),
portfolios AS (
    -- Alle Portfolios aus positions_with_weeks
    SELECT DISTINCT portfolio
    FROM positions_with_weeks
),
isins AS (
    -- Alle ISINs aus positions_with_weeks
    SELECT DISTINCT isin
    FROM positions_with_weeks
),
week_portfolio_isin AS (
    -- Gerüst: Jede Kombination aus Kalenderwoche, Portfolio und ISIN
    SELECT
        cw.calendar_week,
        p.portfolio,
        i.isin
    FROM calendar_weeks cw
    CROSS JOIN portfolios p
    CROSS JOIN isins i
),
positions AS (
    -- Aggregiere Positionen pro ISIN, Portfolio und buy_week
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
    -- Wöchentliche Trades
    SELECT
        isin,
        calendar_week,
        close,
        previous_close
    FROM {{ ref('int_trades_weekly') }}
),
filtered_positions AS (
    -- Filtere Positionen, wo buy_week <= calendar_week, und füge Gerüst hinzu
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
    -- Füge close und previous_close hinzu, verwende buy_price als Fallback
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
    WHERE fp.size IS NOT NULL -- Entferne Zeilen ohne aktive Positionen
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

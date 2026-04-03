{{ config(materialized='table') }}

WITH trades_with_week AS (
    SELECT
        isin,
        trade_time,
        price,
        CONCAT(EXTRACT(YEAR FROM trade_time), '-', LPAD(EXTRACT(WEEK FROM trade_time)::TEXT, 2, '0')) AS calendar_week
    FROM {{ ref('stg_trades') }}
),

weekly_ohlc AS (
    SELECT
        isin,
        calendar_week,
        FIRST_VALUE(price) OVER (PARTITION BY isin, calendar_week ORDER BY trade_time 
                                 ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) AS open,
        LAST_VALUE(price) OVER (PARTITION BY isin, calendar_week ORDER BY trade_time 
                                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS close,
        MAX(price) OVER (PARTITION BY isin, calendar_week) AS high,
        MIN(price) OVER (PARTITION BY isin, calendar_week) AS low
    FROM trades_with_week
    QUALIFY ROW_NUMBER() OVER (PARTITION BY isin, calendar_week ORDER BY trade_time DESC) = 1
)

SELECT
    ohlc.isin,
    ohlc.calendar_week,
    ohlc.open,
    ohlc.close,
    ohlc.high,
    ohlc.low,
    LAG(ohlc.close) OVER (PARTITION BY ohlc.isin ORDER BY ohlc.calendar_week) AS previous_close
FROM weekly_ohlc ohlc

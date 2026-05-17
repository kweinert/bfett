# Refactor: dbt → lea Migration Plan

## Directory structure

```
transform/
├── staging/
│   ├── transactions.sql.jinja
│   ├── cash.sql.jinja
│   ├── active_positions.sql.jinja
│   └── isin_info.sql.jinja
├── core/
│   ├── weeks.sql.jinja
│   ├── instruments.sql.jinja
│   └── ohlc_weekly.sql.jinja
└── mart/
    ├── portfolios.sql.jinja
    ├── cash_weekly.sql.jinja
    └── active_positions_weekly.sql.jinja
```

## `.env` variables required by lea

| Variable | Value | Purpose |
|---|---|---|
| `LEA_WAREHOUSE` | `duckdb` | Warehouse backend for lea |
| `LEA_DUCKDB_PATH` | (user-defined) | Path to DuckDB database file |

Existing `.env` vars (`TRANSACTIONS_RAW_DIR`, `LSX_RAW_DIR`, etc.) remain unchanged. SQL templates reference them via `{{ env["VAR_NAME"] }}`.

## staging/ — 4 files (new, `.sql.jinja`)

Each reads a CSV using the `TRANSACTIONS_RAW_DIR` env var:

```sql
SELECT * FROM read_csv_auto(
    '{{ env["TRANSACTIONS_RAW_DIR"] }}/<table>.csv',
    delim=';', decimal_separator=',', na=''
)
```

| File | CSV | Tests |
|---|---|---|
| `transactions.sql.jinja` | `transactions_raw.csv` | `#NO_NULLS` on `isin, portfolio, size, date, amount, broker, type`; `#SET{'buy','sell','deposit','withdrawal','other'}` on `type` |
| `cash.sql.jinja` | `cash.csv` | `#NO_NULLS` on `date, cash, portfolio` |
| `active_positions.sql.jinja` | `active_positions.csv` | `#NO_NULLS` on `isin, portfolio, size, buy_date, buy_price` |
| `isin_info.sql.jinja` | `isin_info.csv` | `#UNIQUE`, `#NO_NULLS` on `isin`; `#NO_NULLS` on `name`; `#SET{'AKTIE','EXCHANGE','FONDS','BONDS'}` on `gattung` |

## core/ — 3 files (new, `.sql.jinja`)

### `core/weeks.sql.jinja`

Week dimension from min trade date to today.

```sql
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
```

Tests: `#NO_NULLS`, `#UNIQUE` on `calendar_week`; `#NO_NULLS` on `from_date, until_date`.

### `core/instruments.sql.jinja`

ISINs with name and category, derived from staging. Uses `index_membership` from the LSX universe PDF instead of the manual `invest_ideas` table.

```sql
SELECT DISTINCT
    t.isin,
    COALESCE(i.name, t.isin) AS name,
    COALESCE(i.index_membership, '(ohne Idee)') AS category
FROM staging.transactions t
LEFT JOIN staging.isin_info i ON i.isin = t.isin
```

Tests: `#NO_NULLS`, `#UNIQUE` on `isin`; `#NO_NULLS` on `name, category`.

### `core/ohlc_weekly.sql.jinja`

Incremental OHLC, reads parquet via `LSX_RAW_DIR` env var, joins `core.instruments` for ISIN filter. Filters parquet reads with a `trade_time >= CURRENT_DATE - 14` clause to allow DuckDB's columnar pushdown to skip old row groups/files.

```sql
WITH trades_with_week AS (
    SELECT t.isin, t.trade_time, t.price, w.calendar_week
    FROM read_parquet('{{ env["LSX_RAW_DIR"] }}/*.parquet') t
    JOIN core.weeks w ON t.trade_time BETWEEN w.from_date AND w.until_date
    WHERE t.isin IN (SELECT isin FROM core.instruments)
      AND t.trade_time >= CURRENT_DATE - 14  -- DuckDB pushdown on parquet stats
),
weekly_ohlc AS (
    SELECT
        isin,
        calendar_week,
        FIRST_VALUE(price) OVER (PARTITION BY isin, calendar_week ORDER BY trade_time) AS open,
        LAST_VALUE(price) OVER (PARTITION BY isin, calendar_week ORDER BY trade_time
                                ROWS BETWEEN UNBOUNDED PRECEDING AND UNBOUNDED FOLLOWING) AS close,
        MAX(price) OVER (PARTITION BY isin, calendar_week) AS high,
        MIN(price) OVER (PARTITION BY isin, calendar_week) AS low
    FROM trades_with_week
    QUALIFY ROW_NUMBER() OVER (PARTITION BY isin, calendar_week ORDER BY trade_time DESC) = 1
)
SELECT
    isin,
    -- #INCREMENTAL
    calendar_week,
    open,
    close,
    high,
    low,
    LAG(close) OVER (PARTITION BY isin ORDER BY calendar_week) AS previous_close
FROM weekly_ohlc
ORDER BY isin, calendar_week
```

Tests: `#NO_NULLS` on `isin, calendar_week, open, close, high, low`.

## mart/ — 3 files (2 adapted from existing dbt models, 1 new)

### `mart/portfolios.sql.jinja` (new)

```sql
SELECT DISTINCT portfolio AS name FROM staging.transactions ORDER BY name
```

Tests: `#NO_NULLS`, `#UNIQUE` on `name`.

### `mart/cash_weekly.sql.jinja` (adapted)

Replace `{{ ref('cash') }}` => `staging.cash`, inline `generate_series` => `core.weeks`, remove `{{ config(...) }}`.

Tests: `#NO_NULLS` on `portfolio, calendar_week, cash`.

### `mart/active_positions_weekly.sql.jinja` (adapted)

Replace `{{ ref('active_positions') }}` => `staging.active_positions`, `{{ ref('isin_info') }}` and `{{ ref('invest_ideas') }}` => single JOIN on `core.instruments`, `{{ ref('int_trades_weekly') }}` => `core.ohlc_weekly`, remove `{{ config(...) }}`.

Tests: `#NO_NULLS` on `isin, name, category, portfolio, calendar_week, size, buy_in, close_value, previous_close_value`.

## Makefile

Two targets + `all`:

| Target | Commands | Description |
|---|---|---|
| `ingest` | `Rscript ingest/lsx_trades.R` + `Rscript ingest/transactions.R` + `Rscript ingest/universe.R` | Fetches new trade data from GitHub, syncs Google Sheets, updates `isin_info` monthly |
| `transform` | `touch transform/staging/*.sql.jinja transform/core/*.sql.jinja transform/mart/*.sql.jinja` + `lea run --scripts transform --incremental calendar_week $$(date +%G-%V)` | `touch` forces lea to re-run all scripts (their modification time is bumped); lea's `--incremental` keeps `ohlc_weekly` efficient via `DELETE WHERE + INSERT` |
| `all` | `ingest` + `transform` | Complete refresh |

Usage:

```sh
make ingest      # fetch new data
make transform   # update DuckDB (incremental)
make all         # both
```

Rationale for `touch` + `--incremental` approach:
- `touch` makes every SQL file appear modified, so lea includes all scripts in the run set
- Without `touch`, lea would skip scripts whose audit tables exist and whose SQL is unchanged — staging models that read CSVs would never re-run when CSV data changes
- `--incremental calendar_week $(date +%G-%V)` ensures `core.ohlc_weekly` only computes the current week (lea's `delete_and_insert` promotion replaces only that week's data in the table)
- Other models (staging, core non-incremental) run as `CREATE OR REPLACE TABLE` — full refresh, negligible data

## Delete

| Path | Reason |
|---|---|
| `transform/intermediate/int_trades_weekly.sql` | Replaced by `core/ohlc_weekly.sql.jinja` |
| `transform/scripts/` (entire dbt layout) | Replaced by new `staging/`, `core/`, `mart/` |
| `rpkgs/bfett.app/R/rebal_ui.R` | Module removed from dashboard |
| `rpkgs/bfett.app/R/rebal_srv.R` | Module removed from dashboard |
| `rpkgs/bfett.app/man/rebal_ui.Rd` | Orphaned documentation |
| `rpkgs/bfett.app/man/rebal_srv.Rd` | Orphaned documentation |

## Dashboard code changes (`rpkgs/bfett.app/`)

| File | Change |
|---|---|
| `R/bfett_app.R:15-16` | Replace hardcoded `dbdir` with `Sys.getenv("LEA_DUCKDB_PATH", unset = "data/bfett.duckdb")` |
| `R/bfett_app.R:43` | Remove `rebal_ui(id="rebal"),` |
| `R/bfett_app.R:55` | Remove `rebal_srv(id="rebal", r=r)` |
| `NAMESPACE:9-10` | Remove `export(rebal_srv)` and `export(rebal_ui)` |
| `R/pfolioselector_ui.R:12` | Replace inline SQL with `dbReadTable(con, "mart.portfolios")[["name"]]` |
| `R/overview_srv.R:11-12` | `"active_positions_weekly"` => `"mart.active_positions_weekly"`, same for `cash_weekly` |
| `R/treemap_srv.R:14-15` | Same schema-qualified change |
| `R/val_pfoliovalue.R` | `FROM active_positions_weekly` => `FROM mart.active_positions_weekly`, same for `cash_weekly` |
| `R/val_irr.R:26` | `FROM transactions` => `FROM staging.transactions` |

## `ingest/universe.R`

Monthly isin_info refresh (unchanged from original plan):

```r
#!/usr/bin/env Rscript
library(bfett)

readRenviron(".env")
output_dir <- Sys.getenv("TRANSACTIONS_RAW_DIR")
target_file <- file.path(output_dir, "isin_info.csv")

if (file.exists(target_file)) {
  mtime <- file.mtime(target_file)
  if (format(mtime, "%Y-%m") == format(Sys.Date(), "%Y-%m")) {
    message("isin_info already updated this month, skipping")
    quit(save = "no", status = 0)
  }
}

try_date <- Sys.Date()
pdf_path <- NULL
for (i in 0:7) {
  d <- try_date - i
  url <- sprintf("https://www.ls-x.de/media/lsx/stammdaten%s.pdf", format(d, "%Y%m%d"))
  resp <- httr::HEAD(url)
  if (httr::status_code(resp) == 200) {
    pdf_path <- tempfile(fileext = ".pdf")
    download.file(url, pdf_path, mode = "wb", quiet = TRUE)
    break
  }
}
if (is.null(pdf_path)) stop("Could not find LSX universe PDF")

process_universe(pdf_path, seeds = output_dir)
message("✅ isin_info updated from LSX universe PDF")
```

## Migration sequence

1. Create `transform/staging/*.sql.jinja` (4 files)
2. Create `transform/core/*.sql.jinja` (3 files)
3. Create `transform/mart/*.sql.jinja` (3 files, adapted from existing dbt models)
4. Delete old dbt files (`transform/intermediate/`, `transform/scripts/`)
5. Update dashboard code (`rpkgs/bfett.app/`) — schema-qualified table names, `LEA_DUCKDB_PATH` env var, remove rebal module
6. Delete dashboard rebal files (`rebal_ui.R`, `rebal_srv.R`, their `.Rd` docs)
7. Create `ingest/universe.R`
8. Run `make all` to verify

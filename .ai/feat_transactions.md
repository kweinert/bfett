# Refactor: process_transactions.R

## Overview

Refactor `rpkgs/bfett/R/process_transactions.R` to:
1. Add `@importFrom data.table fread fwrite rbindlist setDT` roxygen2 tags
2. Replace `utils::read.csv` / `utils::write.csv` with `data.table::fread` / `data.table::fwrite` (European CSV: `sep = ";"`, `dec = ","`)
3. Replace all `transform()` / `subset()` / `aggregate()` / `do.call(rbind)` with data.table syntax
4. Drop `data.table::` prefix where `@importFrom` provides direct access

## Changes

### 1. Roxygen block (before `@export`)

Add:
```r
#' @importFrom data.table fread fwrite rbindlist setDT
#' @importFrom utils tail head
```

### 2. Input CSV read (line 26)

```r
# Before:
transactions <- utils::read.csv(transactions, na.strings="")

# After:
transactions <- fread(transactions, sep = ";", dec = ",", na.strings = "")
```

### 3. `setDT` call (line 37) and column subset (line 38)

```r
# Before:
transactions <- transactions[,req_cn]
data.table::setDT(transactions)

# After:
setDT(transactions)
transactions <- transactions[, ..req_cn]
```

The `..req_cn` prefix tells data.table that `req_cn` is a variable in the calling scope, not a column name. `setDT()` must come first so `transactions` is a data.table when `..req_cn` is evaluated.

### 4. Outer `split()` calls (lines 47, 116)

Switch both calls from base R `split()` to `split.data.table` to preserve `data.table` class inside helper functions:

```r
# Before (both lines 47 and 116):
split(transactions, transactions$portfolio)

# After (both lines):
split(transactions, by = "portfolio")
```

This ensures `dat` inside `one_portf_cash` and `one_portf_trades` is already a `data.table`, making the chains in sections 5, 7, and 8 work without extra `setDT()`.

### 5. `one_portf_cash` function (lines 40-46)

```r
# Before:
the_sign <- c(deposit=1, buy=-1, other=1, sell=1, withdraw=-1)
ans <- transform(dat, cash = amount*the_sign[type]) |>
    stats::aggregate(cash ~ date, data=_, FUN=sum)
ans[order(ans[["date"]]),] |>
    transform(cash=cumsum(cash), portfolio=dat[1,"portfolio"])

# After:
the_sign <- c(deposit=1, buy=-1, other=1, sell=1, withdraw=-1)
dat[, cash := amount * the_sign[type]
    ][, .(cash = sum(cash)), by = date
    ][order(date)
    ][, cash := cumsum(cash)
    ][, portfolio := dat[1, portfolio]]
```

### 6. `rbindlist` call (line 49)

```r
# Before:
data.table::rbindlist()

# After:
rbindlist()
```

### 7. Sells computation (lines 54-56)

```r
# Before:
sells <- subset(dat, type=="sell") |>
    transform(sell_date=date, sell_price=amount/size)
sells <- sells[order(sells[,"sell_date"], decreasing=FALSE),]

# After:
sells <- dat[type == "sell"
    ][, sell_date := date
    ][, sell_price := amount / size
    ][order(sell_date)]
```

### 8. Open positions computation (lines 58-61)

```r
# Before:
open_pos <- subset(dat, type=="buy") |>
    transform(buy_date=date, buy_price=amount/size)
open_pos <- split(open_pos, open_pos[["isin"]]) |>
    lapply(\(x) x[order(x[,"buy_date"]),])

# After:
open_pos <- dat[type == "buy"
    ][, buy_date := date
    ][, buy_price := amount / size
    ][order(buy_date)]
open_pos <- split(open_pos, by = "isin")
```

### 9. NA check for `size` before `while` loop (line 75)

Insert before `j <- 1`:

```r
if (anyNA(open_pos[[isin]][["size"]])) {
    na_dates <- open_pos[[isin]][["date"]][is.na(open_pos[[isin]][["size"]])]
    stop("Missing size value(s) for isin=", isin, " on date(s): ", paste(na_dates, collapse = ", "))
}
```

### 10. `tail()` in `one_sell` (lines 93, 95)

```r
# Before:
open_pos[[isin]] <<- utils::tail(open_pos[[isin]], -j)

# After:
open_pos[[isin]] <<- tail(open_pos[[isin]], -j)
```

```r
# Before:
open_pos[[isin]] <<- utils::tail(open_pos[[isin]], -j+1)

# After:
open_pos[[isin]] <<- tail(open_pos[[isin]], -j+1)
```

### 11. `closed_trades` result (line 105)

```r
# Before:
do.call(what=rbind) |>
    transform(portfolio=dat[1,"portfolio"])

# After:
rbindlist()[, portfolio := dat[1, portfolio]]
```

### 12. `active_positions` result (lines 109-112)

```r
# Before:
active_positions=do.call(rbind, open_pos) |>
    subset(size>tol_amount) |>
    transform(date=NULL, amount=NULL, type=NULL)
rownames(active_positions) <- NULL

# After:
active_positions <- rbindlist(open_pos)[size > tol_amount
    ][, date := NULL
    ][, amount := NULL
    ][, type := NULL]
```

### 13. `do.call(rbind)` in outer scope (lines 119-125)

Replace three `do.call(what=rbind)` calls with `rbindlist()`:

```r
# Before:
active_positions <- lapply(res, \(x) x[["active_positions"]]) |>
    do.call(what=rbind)
rownames(active_positions) <- NULL

closed_trades <- lapply(res, \(x) x[["closed_trades"]]) |>
    do.call(what=rbind)
rownames(closed_trades) <- NULL

# After:
active_positions <- rbindlist(lapply(res, \(x) x[["active_positions"]]))
closed_trades <- rbindlist(lapply(res, \(x) x[["closed_trades"]]))
```

### 14. Output CSVs (lines 128-130)

```r
# Before:
utils::write.csv(x=cash, file=file.path(output_dir, "cash.csv"), na="", row.names=FALSE)
utils::write.csv(x=active_positions, file=file.path(output_dir, "active_positions.csv"), na="", row.names=FALSE)
utils::write.csv(x=closed_trades, file=file.path(output_dir, "closed_trades.csv"), na="", row.names=FALSE)

# After:
fwrite(cash, file.path(output_dir, "cash.csv"), sep = ";", dec = ",", na = "", row.names = FALSE)
fwrite(active_positions, file.path(output_dir, "active_positions.csv"), sep = ";", dec = ",", na = "", row.names = FALSE)
fwrite(closed_trades, file.path(output_dir, "closed_trades.csv"), sep = ";", dec = ",", na = "", row.names = FALSE)
```

### 15. Update test files

Add `library(data.table)` and switch CSV reads to `fread()` with European format.

#### `test_crwd.R`

After `library(tinytest)`, add `library(data.table)`.

```r
# Before:
ap <- read.csv(file.path(tmp_dir, "active_positions.csv"))

# After:
ap <- fread(file.path(tmp_dir, "active_positions.csv"), sep = ";", dec = ",")
```

```r
# Before:
closed <- read.csv(file.path(tmp_dir, "closed_trades.csv"))

# After:
closed <- fread(file.path(tmp_dir, "closed_trades.csv"), sep = ";", dec = ",")
```

No column indexing changes needed — `test_crwd.R` uses `$` syntax (`closed$isin`) which works with both data.frame and data.table.

#### `test_xiaomi.R`

After `library(tinytest)`, add `library(data.table)`.

Switch CSV reads and update column indexing from `df[,"col"]` to `df[["col"]]`:

```r
# Before (read):
ct <- utils::read.csv(file.path(tmp_dir, "closed_trades.csv"))

# After (read):
ct <- fread(file.path(tmp_dir, "closed_trades.csv"), sep = ";", dec = ",")
```

All `ct[,"col"]` → `ct[["col"]]` throughout:

| Before | After |
|---|---|
| `is.character(ct[,"isin"])` | `is.character(ct[["isin"]])` |
| `is.numeric(ct[,"buy_price"])` | `is.numeric(ct[["buy_price"]])` |
| `is.character(ct[,"buy_date"])` | `is.character(ct[["buy_date"]])` |
| `is.numeric(ct[,"size"])` | `is.numeric(ct[["size"]])` |
| `is.character(ct[,"sell_date"])` | `is.character(ct[["sell_date"]])` |
| `is.numeric(ct[,"sell_price"])` | `is.numeric(ct[["sell_price"]])` |
| `is.character(ct[,"portfolio"])` | `is.character(ct[["portfolio"]])` |
| `ct[1,"isin"]` | `ct[["isin"]][1]` |
| `ct[1,"buy_price"]` | `ct[["buy_price"]][1]` |
| `ct[1,"buy_date"]` | `ct[["buy_date"]][1]` |
| `ct[1,"size"]` | `ct[["size"]][1]` |
| `ct[1,"sell_date"]` | `ct[["sell_date"]][1]` |
| `ct[1,"sell_price"]` | `ct[["sell_price"]][1]` |
| `ct[1,"portfolio"]` | `ct[["portfolio"]][1]` |

```r
# Before (read):
ap <- utils::read.csv(file.path(tmp_dir, "active_positions.csv"))

# After (read):
ap <- fread(file.path(tmp_dir, "active_positions.csv"), sep = ";", dec = ",")
```

All `ap[,"col"]` → `ap[["col"]]` and `ct[,"col"]` → `ct[["col"]]` (same pattern):

| Before | After |
|---|---|
| `is.character(ct[,"isin"])` | `is.character(ct[["isin"]])` |
| `is.numeric(ct[,"buy_price"])` | `is.numeric(ct[["buy_price"]])` |
| `is.character(ct[,"buy_date"])` | `is.character(ct[["buy_date"]])` |
| `is.numeric(ct[,"size"])` | `is.numeric(ct[["size"]])` |
| `is.character(ct[,"portfolio"])` | `is.character(ct[["portfolio"]])` |
| `ap[1,"isin"]` | `ap[["isin"]][1]` |
| `ap[1,"buy_price"]` | `ap[["buy_price"]][1]` |
| `ap[1,"buy_date"]` | `ap[["buy_date"]][1]` |
| `ap[1,"size"]` | `ap[["size"]][1]` |
| `ap[1,"portfolio"]` | `ap[["portfolio"]][1]` |

```r
# Before (read):
cash <- utils::read.csv(file.path(tmp_dir, "cash.csv"))

# After (read):
cash <- fread(file.path(tmp_dir, "cash.csv"), sep = ";", dec = ",")
```

```r
# Before (order):
cash <- cash[order(cash[,"date"]),]

# After (order):
cash <- cash[order(date)]
```

All `cash[,"col"]` → `cash[["col"]]`:

| Before | After |
|---|---|
| `is.numeric(cash[,"cash"])` | `is.numeric(cash[["cash"]])` |
| `is.character(cash[,"date"])` | `is.character(cash[["date"]])` |
| `is.character(cash[,"portfolio"])` | `is.character(cash[["portfolio"]])` |
| `expect_equal(cash[,"cash"], ...)` | `expect_equal(cash[["cash"]], ...)` |
| `all(cash[,"portfolio"]=="nert")` | `all(cash[["portfolio"]]=="nert")` |
| `all(cash[,"date"]==expected_dates)` | `all(cash[["date"]]==expected_dates)` |

### 16. Run tests

Run the three test files that exercise `process_transactions`:

```bash
Rscript -e 'tinytest::run_test_file("rpkgs/bfett/inst/tinytest/test_msft.R")'
Rscript -e 'tinytest::run_test_file("rpkgs/bfett/inst/tinytest/test_crwd.R")'
Rscript -e 'tinytest::run_test_file("rpkgs/bfett/inst/tinytest/test_xiaomi.R")'
```

All must pass before closing the refactor.

## Design Decisions

- **European CSV format**: semicolon separator (`sep = ";"`) and comma decimal point (`dec = ","`) throughout the pipeline (matches `ingest/transactions.R`)
- **Data.table grouping**: all `split()` calls use `split.data.table` (`by = `) to preserve data.table class throughout
- **Chained `data.table[...][...]` syntax**: replaces nested `transform()` / `subset()` pipes
- **No rownames**: data.table doesn't use rownames, so `rownames(x) <- NULL` lines are unnecessary

# Fix: `read_gsheet` returns list columns instead of atomic vectors

## Root Cause

Line 98 in `rpkgs/bfett/R/read_gsheet.R`:
```r
df <- as.data.frame(do.call(rbind, data_raw$values), stringsAsFactors = FALSE)
```

When `content(resp, "parsed")` returns `data_raw$values` as a list of lists, and inner lists contain mixed atomic types (e.g. character headers + numeric data), `do.call(rbind, ...)` creates a matrix of type `"list"`. `as.data.frame()` on a list-matrix produces list columns.

## Solution: Switch to CSV Export

Replace the Sheets API `values` endpoint with the Google Sheets CSV export URL. `data.table::fread()` handles type conversion natively — no list columns.

## Implementation Steps

### Step 1: Rewrite `rpkgs/bfett/R/read_gsheet.R`

New control flow:

```
1. JWT auth → access token                         (UNCHANGED)
2. replace "sheet_name" parameter by "gid", default=0
3. CSV export                                       (REPLACES /values/ endpoint)
   GET https://docs.google.com/spreadsheets/d/{id}/export?format=csv&gid={gid}
   Bearer token auth (same as current)
4. Parse CSV                                        (REPLACES do.call(rbind, ...))
   use data.table::fread()
5. return data.table. do not check column names. 
```

**Changes to function signature:**
- Remove `range` parameter
- replace `sheet_name` by `gid` (default 0)
- Keep `spreadsheet_id`, `json_key_path`

**What gets removed:**
- `range` parameter and all range-handling logic
- `do.call(rbind, data_raw$values)` and header-mangling
- The `%||%` operator usage

**What gets added:**
- CSV export fetch:
  ```r
  url <- paste0("https://docs.google.com/spreadsheets/d/", spreadsheet_id,
                "/export?format=csv&gid=", gid)
  ```

### Step 2: Update `ingest/transactions.R`

- Replace `sheet_name` logic with `gid`:
  ```r
  gid <- as.integer(Sys.getenv("TRANSACTIONS_SHEET_GID", unset = "0"))
  ```
- Change call from `sheet_name = sheet_name` to `gid = gid`
- Drop `TRANSACTIONS_SHEET_NAME` env var logic
- Remove `sheet_name` variable entirely
- Spreadsheet ID extraction and error handling stay unchanged

### Step 3: Add `TRANSACTIONS_SHEET_GID` to `.env`

```bash
TRANSACTIONS_SHEET_GID=0
```

### Step 4: Update roxygen docs in `read_gsheet.R`

- Update `@param` docs: replace `sheet_name` + `range` with `gid`
- Update `@return`: change "A base R data.frame" to "A data.table"
- Update `@examples`:
  ```r
  #'   df <- read_gsheet(
  #'     spreadsheet_id = "1aBcD1234EfGh5678IjKlMnOpQrStUvWxYz",
  #'     gid            = 0,
  #'     json_key_path  = "service-account-key.json"
  #'   )
  ```
- Update `@importFrom`: remove unused `jsonlite::fromJSON` (still needed for key parsing)

### Step 5: No changes to `rpkgs/bfett/DESCRIPTION`

- All current imports remain: `data.table`, `httr`, `jsonlite`, `jose`, `openssl`, `pdftools`

### Step 6: No changes to `rpkgs/bfett/NAMESPACE`

- All current imports remain (`httr`, `jsonlite`, `jose`, `openssl`)
- `fread()` called as `data.table::fread()` (namespace prefix)

### Step 7: Create `rpkgs/bfett/inst/tinytest/test_gsheet.R`

```r
library(tinytest)

readRenviron(".env")
sheet_url <- Sys.getenv("TRANSACTIONS_SHEET_URL")
json_key_path <- Sys.getenv("GOOGLE_SERVICE_ACCOUNT_KEY")

if (sheet_url == "" || json_key_path == "") {
  exit_file("Skipping: missing credentials in .env")
}

spreadsheet_id <- sub(".*spreadsheets/d/([^/]+).*", "\\1", sheet_url)

dat <- read_gsheet(
  spreadsheet_id = spreadsheet_id,
  gid            = 0,
  json_key_path  = json_key_path
)

expect_true(inherits(dat, "data.table"))
expect_true(nrow(dat) > 0)
expect_true(ncol(dat) > 0)
expect_true(!any(sapply(dat, is.list)))
```

## Design Decisions

| Decision | Outcome |
|---|---|
| **Approach** | CSV export (not fixing `do.call(rbind, ...)`) |
| **Parameter** | Replace `sheet_name` + `range` with `gid` (default 0) |
| **Parser** | `data.table::fread()` |
| **Return type** | `data.table`, no `make.names()` or column cleaning |
| **Auth scope** | Keep `spreadsheets.readonly` |
| **Auth error** | `stop()` on http_error (same pattern) |
| **Caller** | `gid = as.integer(Sys.getenv("TRANSACTIONS_SHEET_GID", unset = "0"))` |
| **`.env`** | Add `TRANSACTIONS_SHEET_GID=0` |
| **Test path** | `readRenviron(".env")` (relative to working dir) |
| **Test assertion** | `expect_true(!any(sapply(dat, is.list)))` |
| **No other callers** | Only `ingest/transactions.R` calls `read_gsheet` |

# Feature: Google Sheets Transaction Ingestion

## Overview

Create `bfett/ingest/transactions.R` to:
1. Authenticate with Google using `gcloud` CLI
2. Read transaction data from a Google Sheet via Google Sheets API v4
3. Transform data using existing `process_transactions()` function
4. Output CSVs to `bfett/data/raw/transactions/` and `bfett/seeds/`

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     Docker Container                         │
│                                                             │
│  ┌─────────────┐    ┌──────────────┐    ┌─────────────┐  │
│  │ gcloud CLI  │───▶│ R Script     │───▶│ CSVs        │  │
│  │ (token)     │    │ transactions │    │ (output)    │  │
│  └─────────────┘    └──────────────┘    └─────────────┘  │
│         │                  │                               │
│         ▼                  ▼                               │
│  ┌─────────────┐    ┌──────────────┐                      │
│  │ Service     │    │ httr +       │                      │
│  │ Account Key │    │ data.table   │                      │
│  └─────────────┘    └──────────────┘                      │
└─────────────────────────────────────────────────────────────┘
                    ▲
                    │ Mounted volumes / secrets
                    ▼
         ┌──────────────────┐
         │ Host filesystem  │
         │ - service key   │
         │ - .env config   │
         │ - data output   │
         └──────────────────┘
```

## Files to Create/Modify

| File | Action | Description |
|------|--------|-------------|
| `bfett/ingest/transactions.R` | Create | New script for Google Sheets ingestion |
| `bfett/Dockerfile` | Modify | Add gcloud SDK + Google auth |
| `bfett/.env` | Modify | Add new environment variables |
| `bfett/bfett.sh` | Modify | Add new command for transactions |
| `bfett/scripts/update_transactions.sh` | Create | Wrapper script for Docker |
| `bfett/.gitignore` | Modify | Exclude service account key |

## Implementation Steps

### Step 1: Update `.env`

Add these environment variables:

```bash
# Google Sheets
TRANSACTIONS_SHEET_URL=https://docs.google.com/spreadsheets/d/YOUR_SHEET_ID/edit
GOOGLE_SERVICE_ACCOUNT_KEY=/secure/path/service-account-key.json
```

### Step 2: Create `bfett/ingest/transactions.R`

```r
#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(httr)
  library(jsonlite)
  library(data.table)
})

options(warn = 1)

get_access_token <- function() {
  result <- system2(
    "gcloud", 
    args = c("auth", "print-access-token"),
    stdout = TRUE,
    stderr = TRUE
  )
  if (attr(result, "status") != 0) {
    stop("Failed to get access token: ", paste(result, collapse = "\n"))
  }
  return(result[1])
}

extract_sheet_id <- function(url) {
  match <- regmatches(url, regexpr("d/[a-zA-Z0-9_-]+", url))
  sub("d/", "", match)
}

read_google_sheet <- function(sheet_id, access_token, range = "A1:ZZ100000") {
  url <- sprintf(
    "https://sheets.googleapis.com/v4/spreadsheets/%s/values/%s",
    sheet_id,
    URLencode(range, reserved = FALSE)
  )
  
  response <- GET(
    url,
    add_headers(Authorization = paste("Bearer", access_token))
  )
  
  if (status_code(response) != 200) {
    stop("API request failed: ", content(response, "text"))
  }
  
  data <- content(response, "text") |> fromJSON()
  
  if (is.null(data$values) || length(data$values) == 0) {
    stop("No data found in sheet")
  }
  
  values <- data$values
  
  if (nrow(values) == 0) {
    stop("Sheet is empty")
  }
  
  colnames(values) <- values[1, ]
  values <- values[-1, ]
  
  as.data.table(values)
}

ensure_directory <- function(dir_path) {
  if (!dir.exists(dir_path)) {
    dir.create(dir_path, recursive = TRUE)
    message("Created directory: ", dir_path)
  }
}

main <- function() {
  message("Reading configuration")
  if (!file.exists(".env")) stop("Error: .env file not found.")
  readRenviron(".env")
  
  sheet_url <- Sys.getenv("TRANSACTIONS_SHEET_URL")
  key_path <- Sys.getenv("GOOGLE_SERVICE_ACCOUNT_KEY")
  
  if (sheet_url == "") stop("Error: TRANSACTIONS_SHEET_URL not set")
  if (key_path == "") stop("Error: GOOGLE_SERVICE_ACCOUNT_KEY not set")
  if (!file.exists(key_path)) stop("Error: Service account key not found: ", key_path)
  
  message("Authenticating with service account...")
  auth_result <- system2(
    "gcloud", 
    args = c("auth", "activate-service-account", "--key-file", key_path),
    stderr = TRUE
  )
  if (attr(auth_result, "status") != 0) {
    stop("Failed to activate service account: ", paste(auth_result, collapse = "\n"))
  }
  
  message("Getting access token...")
  access_token <- get_access_token()
  
  sheet_id <- extract_sheet_id(sheet_url)
  message("Reading from sheet: ", sheet_id)
  
  dt <- read_google_sheet(sheet_id, access_token)
  message("Read ", nrow(dt), " rows from Google Sheet")
  
  dt[, date := as.Date(date)]
  dt[, size := as.numeric(size)]
  dt[, amount := as.numeric(amount)]
  
  raw_dir <- "bfett/data/raw/transactions"
  ensure_directory(raw_dir)
  
  temp_csv <- file.path(raw_dir, "transactions_raw.csv")
  fwrite(dt, temp_csv, na = "")
  message("Saved raw transactions to: ", temp_csv)
  
  source(file.path("bfett", "dashboard", "rpkgs", "bfett.processes", "R", "process_transactions.R"))
  
  seeds_dir <- "bfett/seeds"
  ensure_directory(seeds_dir)
  
  process_transactions(transactions = temp_csv, seeds = seeds_dir, verbose = TRUE)
  
  message("Transactions ingestion complete.")
}

main()
```

### Step 3: Modify Dockerfile

Add Google Cloud SDK installation after the existing apt-get section (around line 14):

```dockerfile
# Install Google Cloud SDK for gcloud CLI
RUN apt-get update && apt-get install -y \
    gnupg \
    software-properties-common \
    && rm -rf /var/lib/apt/lists/*

# Add Google Cloud SDK repository
RUN echo "deb [signed-by=/usr/share/keyrings/cloud.google.gpg] https://packages.cloud.google.com/apt cloud-sdk main" | \
    tee -a /etc/apt/sources.list.d/google-cloud-sdk.list && \
    curl https://packages.cloud.google.com/apt/doc/apt-key.gpg | \
    apt-key --keyring /usr/share/keyrings/cloud.google.gpg add - && \
    apt-get update && apt-get install -y google-cloud-cli && \
    rm -rf /var/lib/apt/lists/*
```

Add script copy after line 86:

```dockerfile
COPY ./scripts/update_transactions.sh /app/scripts
```

### Step 4: Create `bfett/scripts/update_transactions.sh`

```bash
#!/bin/bash
set -e

echo "Updating transactions from Google Sheets..."

Rscript bfett/ingest/transactions.R

echo "Running dbt..."
dbt run --select transactions

echo "Transactions update complete."
```

### Step 5: Modify `bfett.sh`

Add to case statement (around line 238):

```bash
update-transactions)
    set_image dbt
    check_docker
    run_docker "$1" "-it"
    EXIT_CODE=$?
    ;;
```

Update help text (around line 145):

```bash
echo "  update-transactions   Update transactions from Google Sheets"
```

### Step 6: Security Setup

#### Create Service Account

1. Go to Google Cloud Console > IAM & Admin > Service Accounts
2. Create new service account (e.g., `bfett-sheets`)
3. Grant roles:
   - For Sheets API access: "Viewer" or specific permissions
4. Go to Keys > Add Key > Create New Key > JSON
5. Download the JSON file securely

#### Share Google Sheet

1. Open your Google Sheet
2. Click Share > Share with specific people
3. Add service account email: `bfett-sheets@YOUR_PROJECT.iam.gserviceaccount.com`
4. Set permission to "Viewer"

#### Store Key Securely

```bash
# Set secure permissions
chmod 600 service-account-key.json

# Store outside repo
mv service-account-key.json /secure/path/

# Update .env with actual path
GOOGLE_SERVICE_ACCOUNT_KEY=/secure/path/service-account-key.json
```

### Step 7: Update `.gitignore`

```bash
# Google service account keys
service-account-key.json
*service-account*.json
```

### Step 8: Docker Volume Mounts

Update `bfett.sh` run_docker function to mount the service account key:

```bash
docker run -it \
    --name "$IMAGE" \
    -e GOOGLE_SERVICE_ACCOUNT_KEY=/secrets/service-account-key.json \
    -v "$HOST_DIR/data:$CONTAINER_DIR/data" \
    -v "$HOST_DIR/database:$CONTAINER_DIR/database" \
    -v "$HOST_DIR/logs:$CONTAINER_DIR/logs" \
    -v "$HOST_DIR/seeds:$CONTAINER_DIR/seeds" \
    -v "/path/on/host/service-account-key.json:/secrets/service-account-key.json:ro" \
    --user "$(id -u):$(id -g)" \
    "$IMAGE" \
    "$cmd"
```

## Security Considerations

### Access Token vs JSON Key

| Aspect | JSON Key File | Access Token |
|--------|--------------|-------------|
| Lifetime | Permanent (or with expiry) | 1 hour |
| Storage | File must exist | Memory only |
| If leaked | Permanent access | Limited window |
| Revocable | Delete key | Wait for expiry |

This implementation:
- Uses JSON key file for initial authentication
- Generates short-lived access tokens via `gcloud`
- Tokens expire after 1 hour (script runtime < 1 hour)
- No need to store tokens persistently

### Best Practices

1. **Never commit keys to git** - Already handled by `.gitignore`
2. **Restrict file permissions** - `chmod 600`
3. **Use read-only scope** - Grant minimum required permissions
4. **Key rotation** - Regularly rotate keys in GCP Console
5. **Monitor usage** - Check GCP audit logs for unauthorized access

## Dependencies

### R Packages (already in Dockerfile)
- `httr` - HTTP requests
- `jsonlite` - JSON parsing
- `data.table` - Data manipulation

### System Dependencies
- Google Cloud SDK (`gcloud` CLI)

## Output Files

| File | Location | Description |
|------|----------|-------------|
| `transactions_raw.csv` | `bfett/data/raw/transactions/` | Raw data from Google Sheet |
| `cash.csv` | `bfett/seeds/` | Processed cash positions |
| `active_positions.csv` | `bfett/seeds/` | Current holdings |
| `closed_trades.csv` | `bfett/seeds/` | Completed trades |

## Usage

```bash
# Build image with changes
./bfett.sh build dbt

# Run transactions update
./bfett.sh update-transactions

# Or manually in Docker
docker exec -it bfett-dbt Rscript bfett/ingest/transactions.R
```

## Notes

- Sheet data expected columns: `isin, name, date, size, amount, type, portfolio, broker`
- Script uses existing `process_transactions()` from `bfett.processes` package
- Transaction types supported: `deposit, buy, other, sell, withdraw`
- Supports multiple portfolios

#!/usr/bin/env Rscript

suppressPackageStartupMessages({
  library(bfett)
  library(data.table)
})

options(warn = 1)

main <- function() {
  message("Reading configuration")
  if (!file.exists(".env")) stop("Error: .env file not found.")
  readRenviron(".env")
  sheet_id <- Sys.getenv("TRANSACTIONS_SHEET_ID")
  json_key_path <- Sys.getenv("GOOGLE_SERVICE_ACCOUNT_KEY")
  output_dir <- Sys.getenv("TRANSACTIONS_RAW_DIR")
  gid <- as.integer(Sys.getenv("TRANSACTIONS_SHEET_GID", unset = "0"))

  if (sheet_id == "") stop("Error: Missing TRANSACTIONS_SHEET_ID environment variable. Check .env file.")
  if (json_key_path == "") stop("Error: Missing GOOGLE_SERVICE_ACCOUNT_KEY environment variable. Check .env file.")
  if (output_dir == "") stop("Error: Missing TRANSACTIONS_RAW_DIR environment variable. Check .env file.")

  message("Reading Google Sheet")
  dat <- bfett::read_gsheet(
    spreadsheet_id = sheet_id,
    gid = gid,
    json_key_path = json_key_path
  )
  stopifnot(inherits(dat, "data.frame"))
  if (nrow(dat) == 0) stop("Error: Google Sheet is empty.")

  message("Writing ", nrow(dat), " raw transactions")
  if (!dir.exists(output_dir)) {
    dir.create(output_dir, recursive = TRUE)
    message("Created directory: ", output_dir)
  }
  raw_csv <- file.path(output_dir, "transactions_raw.csv")
  data.table::fwrite(dat, raw_csv, sep = ";", dec = ",", na = "", row.names = FALSE)

  # Process transactions
  message("Processing transactions...")
  bfett::process_transactions(transactions = dat, output_dir = output_dir)

  message("Transaction ingestion complete.")
}

main()

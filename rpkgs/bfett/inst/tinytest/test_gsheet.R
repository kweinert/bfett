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

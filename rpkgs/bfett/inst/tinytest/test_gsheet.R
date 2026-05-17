library(tinytest)

env_fn <- "/home/faucet/.env"
if(!file.exists(env_fn)) exit_file("Skipping: no .env file found.")

readRenviron(env_fn)
sheet_id <- Sys.getenv("TRANSACTIONS_SHEET_ID")
json_key_path <- Sys.getenv("GOOGLE_SERVICE_ACCOUNT_KEY")
if (sheet_id == "" || json_key_path == "") expect_error(
	dat <- read_gsheet(
	  spreadsheet_id = sheet_id,
	  gid            = 0,
	  json_key_path  = json_key_path
	)
)

# this must work inside the container
dat <- read_gsheet(
  spreadsheet_id = sheet_id,
  gid            = 0,
  json_key_path  = json_key_path
)
expect_true(inherits(dat, "data.table"))
expect_true(nrow(dat) > 0)
expect_true(ncol(dat) >= 8)
expect_true(!any(sapply(dat, is.list)))
expect_true("isin" %in% colnames(dat))
expect_true("name" %in% colnames(dat))
expect_true("date" %in% colnames(dat))
expect_true("size" %in% colnames(dat))
expect_true("amount" %in% colnames(dat))
expect_true("type" %in% colnames(dat))
expect_true("portfolio" %in% colnames(dat))
expect_true("broker" %in% colnames(dat))

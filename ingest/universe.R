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
message("isin_info updated from LSX universe PDF")

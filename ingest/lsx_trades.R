#!/usr/bin/env Rscript

suppressPackageStartupMessages({
	library(jsonlite)
	library(httr)
	library(data.table) 
	library(R.utils)
	library(nanoparquet)
})

options(warn = 1)

ensure_directories <- function(raw_dir, tmp_dir) {
  if (!dir.exists(raw_dir)) {
    dir.create(raw_dir, recursive = TRUE)
    message("Created directory: ", raw_dir)
  }
  if (!dir.exists(tmp_dir)) {
    dir.create(tmp_dir, recursive = TRUE)
    message("Created directory: ", tmp_dir)
  }
}

fetch_releases <- function(github_url) {
  all_releases <- list()
  page <- 1
  per_page <- 100
  repeat {
    url <- paste0(github_url, "?per_page=", per_page, "&page=", page)
    message("Fetching page ", page, "...")
    response <- GET(url)
    if (status_code(response) != 200) stop("Error: Failed to fetch releases (Status: ", status_code(response), ")")
    releases_data <- fromJSON(content(response, as = "text", encoding = "UTF-8"), flatten = TRUE)
    if (length(releases_data) == 0) break
    all_releases[[page]] <- releases_data
    links <- headers(response)$link
    if (is.null(links) || !grepl('rel="next"', links))  break
    page <- page + 1
  }
  if (length(all_releases) == 0) stop("Error: No release data found.")
  message("Fetched ", length(all_releases), " release page(s)")
  all_assets <- lapply(all_releases, function(page) {
		release_assets <- page[, "assets"] # a list of data.frames
		url <- sapply(release_assets, \(x) ifelse("browser_download_url" %in% colnames(x), x[1, "browser_download_url"], NA))
		nm <- page[,"name"]
		data.frame(name=nm, browser_download_url=url)
  }) |> do.call(what=rbind) |>
  subset(grepl("\\.csv\\.gz$", browser_download_url))

  if (nrow(all_assets) == 0) {
    warning("No .csv.gz files found in releases.", call.=FALSE)
    return(data.frame(name = character(), browser_download_url = character()))
  }
  message("Found ", nrow(all_assets), " .csv.gz assets")
  all_assets
}

download_csv_gz <- function(url, dest_path) {
  max_retries <- 3
  retry_count <- 0
  
  while (retry_count < max_retries) {
    tryCatch({
      download.file(url, destfile = dest_path, mode = "wb", quiet = TRUE)
      return(TRUE)
    }, error = function(e) {
      retry_count <<- retry_count + 1
      if (retry_count < max_retries) {
        warning("  Retry ", retry_count, "/", max_retries, " for ", basename(dest_path))
      }
    })
  }
  stop("  Failed to download ", url, " after ", max_retries, " attempts: ", url)
}

convert_to_parquet <- function(csv_gz_path, parquet_path) {
    dt <- fread(csv_gz_path)
	if(!inherits(dt, "data.table") || nrow(dt)==0) stop("error reading ", csv_gz_path)

	csv_gz_name <- basename(csv_gz_path)
    filename_date_str <- substr(csv_gz_name, nchar(csv_gz_name) - 16, nchar(csv_gz_name) - 7)
    data_date_str <- strftime(max(dt$tradeTime, na.rm = TRUE), format = "%Y-%m-%d")
    if (data_date_str < filename_date_str) 
		stop("Data contains trade dates ", data_date_str, " older than filename date ", filename_date_str, ". File rejected.")

    write_parquet(dt, parquet_path)
}

main <- function() {
  message("Reading configuration")
  if (!file.exists(".env")) stop("Error: .env file not found.")
  readRenviron(".env")
  github_url <- Sys.getenv("LSX_GITHUB_URL")
  raw_dir <- Sys.getenv("LSX_RAW_DIR")
  tmp_dir <- Sys.getenv("LSX_TMP_DIR")
  if (github_url == "" || raw_dir == "" || tmp_dir == "") {
    stop("Error: Missing required environment variables. Check .env file.")
  }
  
  message("Fetching release data from GitHub API...")
  assets <- fetch_releases(github_url)
  if (nrow(assets) == 0) {
    warning("No releases to process. Exiting.", call.=FALSE)
    return(invisible(NULL))
  }
  
  message("Comparing to stored files...")
  ensure_directories(raw_dir, tmp_dir)
  existing_files <- list.files(raw_dir, pattern = "\\.parquet$", full.names = FALSE)
  if (length(existing_files) > 0) {
    cutoff_date <- basename(existing_files) |> gsub("lsx_trades_", "", x=_) |> gsub("\\.parquet$", "", x=_) |> max()
    message("Found existing files. Only processing files newer than: ", cutoff_date)
    url_basenames <- basename(assets$browser_download_url)
    url_dates <- substring(url_basenames, nchar(url_basenames) - 16, nchar(url_basenames) - 7)
    assets <- assets[url_dates > cutoff_date, ]
    if (nrow(assets) == 0) {
		message("No new releases to process. Exiting.")
	    return(invisible(NULL))
	}
  } 
    
  # updating
  for (i in seq_len(nrow(assets))) tryCatch({
	  download_url <- assets$browser_download_url[i]
	  message("Adding ", download_url)	
	  file_name <- basename(download_url)
	  parquet_name <- sub("\\.csv\\.gz$", "\\.parquet", file_name)
	  parquet_path <- file.path(raw_dir, parquet_name)
	  csv_gz_path <- file.path(tmp_dir, file_name)
	  if (file.exists(csv_gz_path)) 
		  warning("  using cached download ", csv_gz_path, call.=FALSE)
	  else 
		  download_csv_gz(download_url, csv_gz_path)
	  convert_to_parquet(csv_gz_path, parquet_path)
	  message("  SUCCESS")
    }, error = function(e) warning("  FAILED: ", e$message, call.=FALSE)
  
  # clean up & exit
  tmp_files <- list.files(tmp_dir, pattern = "\\.csv\\.gz$", full.names = TRUE)
  if (length(tmp_files) > 0) {
    message("Cleaning up temp directory...")
    file.remove(tmp_files)
  }
  message("LSX Trades ingestion complete.")
}

main()

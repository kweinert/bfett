#!/usr/bin/env Rscript

library(jsonlite)
library(httr)
library(data.table)
library(nanoparquet)

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
  message("Fetching release data from GitHub API...")
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
    warning("No .csv.gz files found in releases.")
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
      message("Downloaded: ", basename(dest_path))
      return(TRUE)
    }, error = function(e) {
      retry_count <<- retry_count + 1
      if (retry_count < max_retries) {
        message("Retry ", retry_count, "/", max_retries, " for ", basename(dest_path))
      }
    })
  }
  
  warning("Failed to download after ", max_retries, " attempts: ", url)
  return(FALSE)
}

convert_to_parquet <- function(csv_gz_path, parquet_path) {
  tryCatch({
    dt <- fread(csv_gz_path)
    write_parquet(dt, parquet_path)
    message("Converted: ", basename(csv_gz_path), " -> ", basename(parquet_path))
    
    file.remove(csv_gz_path)
    message("Deleted: ", basename(csv_gz_path))
    
    return(TRUE)
  }, error = function(e) {
    warning("Failed to convert ", csv_gz_path, ": ", e$message)
    if (file.exists(csv_gz_path)) {
      file.remove(csv_gz_path)
    }
    return(FALSE)
  })
}

main <- function() {
  readRenviron(".env")
  
  github_url <- Sys.getenv("LSX_GITHUB_URL")
  raw_dir <- Sys.getenv("LSX_RAW_DIR")
  tmp_dir <- Sys.getenv("LSX_TMP_DIR")
  
  if (github_url == "" || raw_dir == "" || tmp_dir == "") {
    stop("Error: Missing required environment variables. Check .env file.")
  }
  
  if (!file.exists(".env")) {
    stop("Error: .env file not found.")
  }
  
  message("Starting LSX Trades ingestion...")
  
  ensure_directories(raw_dir, tmp_dir)
  
  assets <- fetch_releases(github_url)
  
  if (nrow(assets) == 0) {
    message("No files to process. Exiting.")
    return(invisible(NULL))
  }
  
  for (i in seq_len(nrow(assets))) {
    file_name <- assets$name[i]
    download_url <- assets$browser_download_url[i]
    
    parquet_name <- sub("\\.csv\\.gz$", "\\.parquet", file_name)
    parquet_path <- file.path(raw_dir, parquet_name)
    csv_gz_path <- file.path(tmp_dir, file_name)
    
    if (file.exists(parquet_path)) {
      message("Parquet already exists, skipping: ", parquet_name)
      next
    }
    
    if (!file.exists(csv_gz_path)) {
      success <- download_csv_gz(download_url, csv_gz_path)
      if (!success) {
        next
      }
    } else {
      message("CSV.GZ already exists, skipping download: ", file_name)
    }
    
    convert_to_parquet(csv_gz_path, parquet_path)
  }
  
  tmp_files <- list.files(tmp_dir, pattern = "\\.csv\\.gz$", full.names = TRUE)
  if (length(tmp_files) > 0) {
    message("Cleaning up temp directory...")
    file.remove(tmp_files)
  }
  
  message("LSX Trades ingestion complete.")
}

main()

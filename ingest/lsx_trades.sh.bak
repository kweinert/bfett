# Required Libraries
library(jsonlite)
library(httr)

# --- Configuration ---
LSX <- "/app/data/lsx_trades"
REPO_URL <- "https://api.github.com/repos/kweinert/lsx_trades/releases"

# 1. Create directory if it doesn't exist
if (!dir.exists(LSX)) {
  dir.create(LSX, recursive = TRUE)
  message("Created directory: ", LSX)
}

# 2. Fetch releases from GitHub API
message("Fetching release data...")
response <- GET(REPO_URL)

if (status_code(response) != 200) {
  stop("Error: Failed to fetch releases from GitHub API (Status: ", status_code(response), ")")
}

# 3. Parse JSON and check content
releases_data <- fromJSON(content(response, as = "text", encoding = "UTF-8"), flatten = TRUE)

if (length(releases_data) == 0) {
  stop("Error: No release data found.")
}

# 4. Extract assets and filter for .csv.gz
# We use 'unnest' logic or access the nested assets list
assets_list <- releases_data$assets

# Combine all assets into one dataframe for easier processing
all_assets <- do.call(rbind, assets_list)

# Filter for files ending in .csv.gz
csv_gz_assets <- all_assets[grepl("\\.csv\\.gz$", all_assets$name), ]

if (nrow(csv_gz_assets) == 0) {
  message("No .csv.gz files found in releases.")
  quit(save = "no", status = 0)
}

# 5. Process each asset (Download if missing)
for (i in 1:nrow(csv_gz_assets)) {
  file_name <- csv_gz_assets$name[i]
  download_url <- csv_gz_assets$browser_download_url[i]
  dest_path <- file.path(LSX, file_name)
  
  if (!file.exists(dest_path)) {
    message("Downloading ", file_name, "...")
    
    # download.file is robust for various protocols
    tryCatch({
      download.file(download_url, destfile = dest_path, mode = "wb", quiet = TRUE)
      message("Successfully downloaded ", file_name)
    }, error = function(e) {
      warning("Failed to download ", file_name, ": ", e$message)
    })
    
  } else {
    message(file_name, " already exists in ", LSX, ", skipping download.")
  }
}

message("Processing complete.")

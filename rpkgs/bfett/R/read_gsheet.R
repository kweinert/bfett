#' Read Google Sheet using Service Account
#'
#' Reads data from a private Google Sheet using a Service Account JSON key file.
#' Uses CSV export endpoint and \code{data.table::fread()} for parsing.
#'
#' @param spreadsheet_id Character. Google Spreadsheet ID (the long string in the URL).
#' @param gid Integer. Sheet grid ID (tab identifier). Default 0 (first sheet).
#' @param json_key_path Character. Path to the Service Account JSON key file.
#'
#' @return A data.table containing the sheet data.
#'
#' @importFrom httr POST GET add_headers http_error status_code content
#' @importFrom jsonlite fromJSON
#' @importFrom jose jwt_encode_sig jwt_claim
#' @importFrom openssl read_key
#'
#' @export
#'
#' @examples
#' \dontrun{
#'   dat <- read_gsheet(
#'     spreadsheet_id = "1aBcD1234EfGh5678IjKlMnOpQrStUvWxYz",
#'     gid            = 0,
#'     json_key_path  = "service-account-key.json"
#'   )
#' }
#'
read_gsheet <- function(spreadsheet_id,
                        gid = 0,
                        json_key_path = "service-account-key.json") {
  message("Authenticating..")
  key <- fromJSON(json_key_path)
  claim <- jwt_claim(
    iss   = key$client_email,
	scope = "https://www.googleapis.com/auth/spreadsheets.readonly https://www.googleapis.com/auth/drive.readonly",
    aud   = "https://oauth2.googleapis.com/token",
    exp   = as.integer(Sys.time()) + 3600,
    iat   = as.integer(Sys.time())
  )
  jwt <- jwt_encode_sig(claim = claim, key = read_key(key$private_key))
  token_resp <- POST(
    url = "https://oauth2.googleapis.com/token",
    body = list(
      grant_type = "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion  = jwt
    ),
    encode = "form"
  )
  token <- content(token_resp, "parsed")$access_token
  if (is.null(token)) stop("Failed to retrieve access token from Google")

  message("Reading...")
  url <- paste0("https://docs.google.com/spreadsheets/d/", spreadsheet_id, "/export?format=tsv&gid=", gid)
  resp <- GET(url, add_headers(Authorization = paste("Bearer", token)))
  if (http_error(resp)) stop(paste("HTTP error", status_code(resp), "-", content(resp, "text")))
  raw_csv <- content(resp, "text")
  data.table::fread(text = raw_csv, sep="\t", dec=",")
}

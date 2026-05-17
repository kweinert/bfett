#' Process transactions
#'
#' Takes "raw" transaction data (isin, name, date, size, amount, type, portfolio, broker) and
#' generates three csv -- cash, active_positions, closed_trades -- in the provided output_dir folder.
#'
#' Is able to handle different portfolios. 
#'
#' closed_trades: Sell Orders are matched with the oldest Buy Order available. 
#' Dividends are ignored for now.
#'
#' cash: is basically the cumulated sum of the transactions. Note that in
#' trade republic there may be differences between "transactions" in the app and
#' account statements. It seems account statements are the "real" thing.
#'
#' @param transactions data.frame or filename
#' @param output_dir character, path to output folder, default dirname(transactions)
#' @param verbose logical, print diagnostic messages
#' @param tol_amount numerical, tolerance for position sizes
#' @return NULL, used for its side effects
#' @importFrom data.table fread fwrite rbindlist setDT
#' @importFrom utils tail head
#' @export
process_transactions <- function(transactions, output_dir=NULL, verbose=FALSE, tol_amount=0.00001) {
	# validate input
	if(is.character(transactions)) {
		stopifnot(length(transactions)==1, file.exists(transactions))
		if(is.null(output_dir)) output_dir <- dirname(transactions)
		transactions <- fread(transactions, sep = ";", dec = ",", na.strings = "")
	}
	stopifnot(is.data.frame(transactions), nrow(transactions)>0)
	req_cn <- c("isin", "date", "size", "amount", "type", "portfolio")
	miss_cn <- setdiff(req_cn, colnames(transactions))
	if(length(miss_cn)) stop("Missing column(s) in transactions: ", paste0(miss_cn, collapse=", "))
	stopifnot(all(unique(transactions[["type"]]) %in% c("deposit", "buy", "other", "sell", "withdraw")))
	stopifnot(dir.exists(output_dir))
	
	# remove unneeded information, enforce data.table
	transactions <- transactions[,req_cn]
	setDT(transactions)
	
	# cash is basically a cumsum()
	one_portf_cash <- function(dat) {
		the_sign <- c(deposit=1, buy=-1, other=1, sell=1, withdraw=-1)
		dat[, cash := amount * the_sign[type]
		    ][, .(cash = sum(cash)), by = date
		    ][order(date)
		    ][, cash := cumsum(cash)
		    ][, portfolio := dat[1, portfolio]]
	}
	cash <- split(transactions, by = "portfolio") |>
		lapply(one_portf_cash) |>
		rbindlist()
	

    # don't know how to avoid the for loop
	one_portf_trades <- function(dat) {
		sells <- dat[type == "sell"
		    ][, sell_date := date
		    ][, sell_price := amount / size
		    ][order(sell_date)]

		open_pos <- dat[type == "buy"
		    ][, buy_date := date
		    ][, buy_price := amount / size
		    ][order(buy_date)]
		open_pos <- split(open_pos, by = "isin")
		
	
		one_sell <- function(i) {
			size <- sells[["size"]][i]
			isin <- sells[["isin"]][i]
			if(verbose) message("i=", i, ", size=", size, ", isin=", isin)
			
			# find out which buys are cleared with this sell.
			#open_dat <- open_pos[[isin]]
			
			#idx <- which(open_dat$buy_date <= sells[i,"sell_date"])
			#browser()
			
			if (anyNA(open_pos[[isin]][["size"]])) {
			    na_dates <- open_pos[[isin]][["date"]][is.na(open_pos[[isin]][["size"]])]
			    stop("Missing size value(s) for isin=", isin, " on date(s): ", paste(na_dates, collapse = ", "))
			}
			j <- 1
			while (size>sum(open_pos[[isin]][["size"]][1:j]) && j<nrow(open_pos[[isin]])) {
				j <- j + 1
				if(verbose) {
					message("    j=", j, ", sum(open_pos[[isin]][1:j, 'size'])=", sum(open_pos[[isin]][["size"]][1:j]))
					Sys.sleep(1)
				}
			}
			if(size-sum(open_pos[[isin]][["size"]][1:j]) > tol_amount) stop("more sold (", size, ") than bought (", sum(open_pos[[isin]][["size"]][1:j]), " isin=", isin)
			ans <- open_pos[[isin]][1:j,c("isin", "buy_price", "buy_date", "size")]
			if(j==1) {
				ans[["size"]][1] <- size
			} else {
				ans[["size"]][j] <- size - sum(ans[["size"]][1:(j-1)])
			}
			j_remain <- open_pos[[isin]][["size"]][j] - ans[["size"]][j]
			#browser()
			if(j_remain<tol_amount) {
				open_pos[[isin]] <<- tail(open_pos[[isin]], -j)
			} else {
				open_pos[[isin]] <<- tail(open_pos[[isin]], -j+1)
				open_pos[[isin]][["size"]][1] <<- j_remain
			}

			merge(ans, sells[i, c("isin", "sell_date", "sell_price")], by="isin")
		}
		
		closed_trades <- if(nrow(sells)>0)
			rbindlist(lapply(seq.int(nrow(sells)), one_sell))[, portfolio := dat[1, portfolio]]
		else
			data.frame()

		active_positions <- rbindlist(open_pos)[size > tol_amount
		    ][, date := NULL
		    ][, amount := NULL
		    ][, type := NULL]
			
		list(closed_trades=closed_trades, active_positions=active_positions)
	}
	res <- split(transactions, by = "portfolio") |>
		lapply(one_portf_trades)

	active_positions <- rbindlist(lapply(res, \(x) x[["active_positions"]]))
	closed_trades <- rbindlist(lapply(res, \(x) x[["closed_trades"]]))

	# write result
	fwrite(cash, file.path(output_dir, "cash.csv"), sep = ";", dec = ",", na = "", row.names = FALSE)
	fwrite(active_positions, file.path(output_dir, "active_positions.csv"), sep = ";", dec = ",", na = "", row.names = FALSE)
	fwrite(closed_trades, file.path(output_dir, "closed_trades.csv"), sep = ";", dec = ",", na = "", row.names = FALSE)
	
}



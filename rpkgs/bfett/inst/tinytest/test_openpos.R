library(tinytest)
library(data.table)

# Error in while (size > sum(open_pos[[isin]][["size"]][1:j]) && j < nrow(open_pos[[isin]])) { : 
#  missing value where TRUE/FALSE needed
# Calls: main ... <Anonymous> -> lapply -> FUN -> rbindlist -> lapply -> FUN
# Execution halted

dat <- fread(sep="\t", input="
  isin	name	date	size	amount	type	portfolio	broker
  US36847Q1013	Geely Auto (ADR)	2025-04-28	3	109.6	buy	nert	tr
  US36847Q1031	Geely Auto (ADR)	2025-08-11	3	118.29	sell	nert	tr
  US36847Q1031	Geely Auto (ADR)	2025-08-13	3	1.45	other	nert	tr
")

tmp_dir <- tempdir()
expect_error(process_transactions(dat, output_dir = tmp_dir, verbose=TRUE))

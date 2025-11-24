#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fganalysis))
suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(dplyr))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) stop("No arguments provided")
params <- fromJSON(args[1])

drug_codes <- params$drug_codes
config_path <- params$config_path

conn <- connect_fgdata(config_path)

tryCatch({
    drugs <- get_drug_purchases(conn, druglist = drug_codes, lazy = TRUE)
    
    count <- drugs %>% count() %>% collect()
    head_data <- drugs %>% head(10) %>% collect()
    
    result <- list(
        status = "success",
        count = as.numeric(count),
        preview = head_data
    )
    cat(toJSON(result, auto_unbox = TRUE))
}, error = function(e) {
    cat(toJSON(list(status = "error", message = e$message), auto_unbox = TRUE))
})

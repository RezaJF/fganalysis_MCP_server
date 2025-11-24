#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fganalysis))
suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(dplyr))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) stop("No arguments provided")
params <- fromJSON(args[1])

lab_id <- params$lab_id
config_path <- params$config_path

conn <- connect_fgdata(config_path)

tryCatch({
    labs <- get_lab_measurements(conn$labs, lablist = lab_id, lazy = TRUE)
    
    # Get count and head
    count <- labs %>% count() %>% collect()
    head_data <- labs %>% head(10) %>% collect()
    
    result <- list(
        status = "success",
        count = as.numeric(count),
        preview = head_data
    )
    cat(toJSON(result, auto_unbox = TRUE))
}, error = function(e) {
    cat(toJSON(list(status = "error", message = e$message), auto_unbox = TRUE))
})

#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fganalysis))
suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(ggplot2))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) stop("No arguments provided")
params <- fromJSON(args[1])

lab_id <- params$lab_id
drug_codes <- params$drug_codes
config_path <- params$config_path
output_file <- params$output_file

conn <- connect_fgdata(config_path)

tryCatch({
    # We need response data to plot distribution
    # Using default windows if not specified, or standard -1,0 to 0.25,1
    response_data <- create_drug_response(
        conn = conn,
        lablist = lab_id,
        druglist = drug_codes,
        before_period = c(-1, 0),
        after_period = c(0.25, 1)
    )
    
    p <- plot_lab_value_distribution(response_data, remove_outliers = TRUE)
    
    ggsave(output_file, plot = p, width = 10, height = 8)
    
    result <- list(
        status = "success",
        output_file = output_file
    )
    cat(toJSON(result, auto_unbox = TRUE))
}, error = function(e) {
    cat(toJSON(list(status = "error", message = e$message), auto_unbox = TRUE))
})

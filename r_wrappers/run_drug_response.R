#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fganalysis))
suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(dplyr))

# Parse arguments
args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) {
  stop("No arguments provided. Expected JSON string.")
}

params <- fromJSON(args[1])

# Extract parameters
lab_id <- params$lab_id
drug_codes <- params$drug_codes
before_window <- params$before_window
after_window <- params$after_window
config_path <- params$config_path
output_prefix <- params$output_prefix

# Connect to data
if (!file.exists(config_path)) {
    # Fallback for testing if config doesn't exist
    stop(paste("Config file not found:", config_path))
}
conn <- connect_fgdata(config_path)

# Run analysis
tryCatch({
    response_data <- create_drug_response(
        conn = conn,
        lablist = lab_id,
        druglist = drug_codes,
        before_period = before_window,
        after_period = after_window
    )
    
    # Summarize
    summarize_drug_response(response_data, out_file_prefix = output_prefix)
    
    # Return result
    result <- list(
        status = "success",
        output_files = list(
            pdf = paste0(output_prefix, "_summary.pdf"),
            tables = paste0(output_prefix, "_tables.txt") # Adjust based on actual output
        )
    )
    cat(toJSON(result, auto_unbox = TRUE))
}, error = function(e) {
    result <- list(status = "error", message = e$message)
    cat(toJSON(result, auto_unbox = TRUE))
})

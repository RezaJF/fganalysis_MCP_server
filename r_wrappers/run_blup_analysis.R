#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fganalysis))
suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(dplyr))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) stop("No arguments provided")
params <- fromJSON(args[1])

lab_id <- params$lab_id
drug_codes <- params$drug_codes
output_dir <- params$output_dir
config_path <- params$config_path

if (!dir.exists(output_dir)) dir.create(output_dir, recursive = TRUE)

conn <- connect_fgdata(config_path)

tryCatch({
    # Get measurements first (recommended workflow)
    measurements <- get_measurements_before_drug(
        conn = conn,
        lablist = lab_id,
        druglist = drug_codes,
        months_before = 3 # Defaulting to 3, could be param
    )
    
    # Add covariates if possible (simplified for now)
    # In a real scenario, we'd want to join covariates here
    
    blup_results <- calculate_blup_slopes(
        data = measurements,
        output_dir = output_dir,
        calculate_qc = TRUE,
        save_model = TRUE
    )
    
    result <- list(
        status = "success",
        output_dir = output_dir,
        concepts = names(blup_results)
    )
    cat(toJSON(result, auto_unbox = TRUE))
}, error = function(e) {
    cat(toJSON(list(status = "error", message = e$message), auto_unbox = TRUE))
})

#!/usr/bin/env Rscript
suppressPackageStartupMessages(library(fganalysis))
suppressPackageStartupMessages(library(jsonlite))
suppressPackageStartupMessages(library(dplyr))
suppressPackageStartupMessages(library(ggplot2))

args <- commandArgs(trailingOnly = TRUE)
if (length(args) == 0) stop("No arguments provided")
params <- fromJSON(args[1])

code <- params$code
config_path <- params$config_path

# Connect to data
conn <- connect_fgdata(config_path)

# Create a safe environment for execution
env <- new.env()
assign("conn", conn, envir = env)
assign("get_lab_measurements", get_lab_measurements, envir = env)
assign("get_drug_purchases", get_drug_purchases, envir = env)
assign("create_drug_response", create_drug_response, envir = env)

# Execute code
tryCatch({
    # We wrap the code to capture the last expression or specific output
    # For simplicity, we assume the code prints JSON or returns a value we can serialize
    # Or we capture stdout.
    
    # Capture output
    output <- capture.output({
        eval(parse(text = code), envir = env)
    })
    
    # Check if the code created any plots (ggsave) or files
    # This is hard to track without explicit return, so we rely on stdout for now
    
    result <- list(
        status = "success",
        stdout = paste(output, collapse = "\n")
    )
    cat(toJSON(result, auto_unbox = TRUE))
}, error = function(e) {
    cat(toJSON(list(status = "error", message = e$message), auto_unbox = TRUE))
})

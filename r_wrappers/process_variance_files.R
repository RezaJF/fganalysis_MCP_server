#!/usr/bin/env Rscript

args_all <- commandArgs(FALSE)
file_arg <- sub("^--file=", "", args_all[grep("^--file=", args_all)][1])
source(file.path(dirname(normalizePath(file_arg)), "common.R"))

run_json_wrapper({
  params <- read_params()

  suppressPackageStartupMessages({
    library(fganalysis)
  })

  output_dir <- params$output_dir %||% "."
  if (!dir.exists(output_dir)) {
    stop(sprintf("output_dir does not exist: %s", output_dir))
  }
  output_dir <- normalizePath(output_dir, mustWork = TRUE)

  pattern <- params$pattern %||% "_variance\\.tsv$"
  generate_plots <- as_scalar_logical(params$generate_plots, FALSE)
  save_normalized <- as_scalar_logical(params$save_normalized, TRUE)

  summary_table <- fganalysis::process_variance_files(
    output_dir = output_dir,
    pattern = pattern,
    generate_plots = generate_plots,
    save_normalized = save_normalized
  )

  output_files <- character()
  if (save_normalized) {
    output_files <- existing_files(list.files(
      path = output_dir,
      pattern = "_qnorm\\.tsv$",
      full.names = TRUE
    ))
  }

  list(
    status = "success",
    output_dir = output_dir,
    pattern = pattern,
    n_files_processed = if (is.null(summary_table)) 0L else nrow(summary_table),
    summary = if (is.null(summary_table)) data.frame() else summary_table,
    output_files = output_files
  )
})

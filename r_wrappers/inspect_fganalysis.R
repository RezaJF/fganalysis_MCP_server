#!/usr/bin/env Rscript

args_all <- commandArgs(FALSE)
file_arg <- sub("^--file=", "", args_all[grep("^--file=", args_all)][1])
source(file.path(dirname(normalizePath(file_arg)), "common.R"))

run_json_wrapper({
  params <- read_params()

  suppressPackageStartupMessages({
    library(fganalysis)
  })

  exported_functions <- getNamespaceExports("fganalysis")
  required_exports <- c(
    "connect_fgdata",
    "get_lab_measurements",
    "get_drug_purchases",
    "create_drug_response",
    "summarize_drug_response",
    "calculate_blup_slopes",
    "get_measurements_before_drug",
    "get_median_pre_drug",
    "expand_atc_codes",
    "get_atc_relationships"
  )

  config_status <- NULL
  if (!is.null(params$config_path)) {
    config_status <- list(
      path = normalizePath(params$config_path, mustWork = FALSE),
      exists = file.exists(params$config_path)
    )
  }

  list(
    status = "success",
    r_version = as.character(getRversion()),
    fganalysis_version = as.character(utils::packageVersion("fganalysis")),
    fganalysis_library_path = find.package("fganalysis"),
    jsonlite_available = requireNamespace("jsonlite", quietly = TRUE),
    required_exports_present = as.list(setNames(
      required_exports %in% exported_functions,
      required_exports
    )),
    exported_function_count = length(exported_functions),
    config = config_status
  )
})

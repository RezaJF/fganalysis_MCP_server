#!/usr/bin/env Rscript

args_all <- commandArgs(FALSE)
file_arg <- sub("^--file=", "", args_all[grep("^--file=", args_all)][1])
source(file.path(dirname(normalizePath(file_arg)), "common.R"))

run_json_wrapper({
  params <- read_params()

  suppressPackageStartupMessages({
    library(fganalysis)
  })

  custom_file <- params$custom_mapping_file %||% NULL
  error_if_not_found <- as_scalar_logical(params$error_if_not_found, FALSE)
  preview_limit <- as_scalar_integer(params$preview_limit, 10)

  mappings <- fganalysis::load_atc_mappings(
    custom_file = custom_file,
    error_if_not_found = error_if_not_found
  )

  preview_codes <- utils::head(names(mappings$mappings), preview_limit)
  preview <- lapply(preview_codes, function(code) mappings$mappings[[code]])
  names(preview) <- preview_codes

  list(
    status = "success",
    version = mappings$version,
    generated_date = as.character(mappings$generated_date),
    source_url = mappings$source_url,
    total_mappings = mappings$total_mappings,
    custom_mapping_file = custom_file,
    preview = preview
  )
})

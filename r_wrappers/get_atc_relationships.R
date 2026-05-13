#!/usr/bin/env Rscript

args_all <- commandArgs(FALSE)
file_arg <- sub("^--file=", "", args_all[grep("^--file=", args_all)][1])
source(file.path(dirname(normalizePath(file_arg)), "common.R"))

run_json_wrapper({
  params <- read_params()

  suppressPackageStartupMessages({
    library(fganalysis)
  })

  atc_codes <- as_character_vector(params$atc_codes, "atc_codes")
  include_hierarchical <- as_scalar_logical(params$include_hierarchical, TRUE)
  require_mapping <- as_scalar_logical(params$require_mapping, FALSE)
  custom_mapping_file <- params$custom_mapping_file %||% NULL

  expanded_codes <- call_supported(
    fganalysis::expand_atc_codes,
    atc_codes,
    include_hierarchical = include_hierarchical,
    verbose = FALSE,
    custom_mapping_file = custom_mapping_file,
    require_mapping = require_mapping
  )

  relationships <- lapply(atc_codes, function(code) {
    relationship <- fganalysis::get_atc_relationships(code)
    relationship$queried_code <- code
    relationship
  })
  names(relationships) <- atc_codes

  list(
    status = "success",
    atc_codes = as_json_array(atc_codes),
    expanded_codes = as_json_array(expanded_codes),
    relationships = relationships
  )
})

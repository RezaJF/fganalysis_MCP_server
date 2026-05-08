#!/usr/bin/env Rscript

args_all <- commandArgs(FALSE)
file_arg <- sub("^--file=", "", args_all[grep("^--file=", args_all)][1])
source(file.path(dirname(normalizePath(file_arg)), "common.R"))

run_json_wrapper({
  params <- read_params()

  suppressPackageStartupMessages({
    library(fganalysis)
    library(dplyr)
  })

  lab_id <- as_character_vector(params$lab_id, "lab_id")
  drug_codes <- as_character_vector(params$drug_codes, "drug_codes")
  months_before <- as.numeric(params$months_before %||% 3)
  config_path <- params$config_path
  output_file <- params$output_file %||% NULL
  if (!is.null(output_file)) {
    ensure_parent_dir(output_file)
  }

  range_sd_filter <- params$range_sd_filter
  if (is.list(range_sd_filter) && length(range_sd_filter) == 0) {
    range_sd_filter <- NULL
  }

  conn <- connect_from_config(config_path)

  measurements <- fganalysis::get_measurements_before_drug(
    conn = conn,
    lablist = lab_id,
    druglist = drug_codes,
    months_before = months_before,
    use_freetext_values = as_scalar_logical(params$use_freetext_values, TRUE),
    use_only_reimbursement = as_scalar_logical(params$use_only_reimbursement, FALSE),
    use_atc_mapping = as_scalar_logical(params$use_atc_mapping, TRUE),
    remove_outliers_sd = as_nullable_numeric(params$remove_outliers_sd),
    winsorize_pct = as_nullable_numeric(params$winsorize_pct),
    range_sd_filter = range_sd_filter
  )

  output_files <- character()
  if (!is.null(output_file)) {
    utils::write.table(
      measurements, file = output_file,
      sep = "\t", row.names = FALSE, quote = FALSE
    )
    output_files <- normalizePath(output_file, mustWork = TRUE)
  }
  output_files <- as_json_array(output_files)

  list(
    status = "success",
    lab_id = lab_id,
    drug_codes = drug_codes,
    months_before = months_before,
    n_individuals = length(unique(measurements$FINNGENID)),
    n_measurements = nrow(measurements),
    n_exposed = sum(!is.na(measurements$first_drug_age)),
    n_unexposed = sum(is.na(measurements$first_drug_age)),
    preview = dataframe_preview(measurements, as_scalar_integer(params$limit, 10)),
    output_files = output_files,
    config_path = normalizePath(config_path, mustWork = TRUE)
  )
})

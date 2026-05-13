#!/usr/bin/env Rscript

args_all <- commandArgs(FALSE)
file_arg <- sub("^--file=", "", args_all[grep("^--file=", args_all)][1])
source(file.path(dirname(normalizePath(file_arg)), "common.R"))

run_json_wrapper({
  params <- read_params()

  suppressPackageStartupMessages({
    library(fganalysis)
  })

  lab_id <- as_character_vector(params$lab_id, "lab_id")
  drug_codes <- as_character_vector(params$drug_codes, "drug_codes")
  output_dir <- ensure_output_dir(params$output_dir)
  config_path <- params$config_path

  conn <- connect_from_config(config_path)

  output <- call_supported(
    fganalysis::get_median_pre_drug,
    conn = conn,
    lablist = lab_id,
    druglist = drug_codes,
    months_before = as.numeric(params$months_before %||% 1),
    remove_outliers_mad_th = as_nullable_numeric(params$remove_outliers_mad_th),
    use_atc_mapping = as_scalar_logical(params$use_atc_mapping, TRUE),
    output_dir = output_dir,
    output_file_prefix = params$output_file_prefix %||% ""
  )

  output_files <- existing_files(file.path(
    output_dir,
    paste0(params$output_file_prefix %||% "", "_", lab_id[[1]], "_DF13_median.tsv")
  ))

  list(
    status = "success",
    lab_id = lab_id,
    drug_codes = drug_codes,
    output_dir = output_dir,
    n_rows = nrow(output),
    output_files = output_files,
    preview = dataframe_preview(output, 10),
    config_path = normalizePath(config_path, mustWork = TRUE)
  )
})

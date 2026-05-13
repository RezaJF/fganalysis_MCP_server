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
  months_before <- as.numeric(params$months_before %||% 1)
  remove_outliers_mad_th <- as.numeric(params$remove_outliers_mad_th %||% 5)
  output_dir <- ensure_output_dir(params$output_dir)
  config_path <- params$config_path
  output_file_prefix <- params$output_file_prefix %||% ""

  conn <- connect_from_config(config_path)

  measurements_before <- call_supported(
    fganalysis::get_measurements_before_drug,
    conn = conn,
    lablist = lab_id,
    druglist = drug_codes,
    months_before = months_before,
    use_atc_mapping = as_scalar_logical(params$use_atc_mapping, TRUE)
  )

  if (as_scalar_logical(params$include_sex_covariates, FALSE) && "cov_pheno" %in% names(conn)) {
    sex_cols <- intersect(c("SEX", "SEX_IMPUTED"), colnames(conn$cov_pheno))
    if (length(sex_cols) > 0) {
      measurements_before <- fganalysis::join_covariates_to_labs(
        lab_data = measurements_before,
        covariates = conn$cov_pheno,
        covariate_cols = sex_cols
      )
    }
  }

  measurements_after <- measurements_before %>%
    dplyr::filter(.data$VALUE %in% fganalysis::filter_outliers_mad(.data$VALUE, th = remove_outliers_mad_th))

  fganalysis::plot_median_pre_drug(
    measurements_before_mad = measurements_before,
    measurements_after_mad = measurements_after,
    output_dir = output_dir,
    output_file_prefix = output_file_prefix
  )

  expected_files <- file.path(
    output_dir,
    c(
      paste0(output_file_prefix, "_mad_distribution.png"),
      paste0(output_file_prefix, "_sex_violin.png")
    )
  )

  list(
    status = "success",
    lab_id = lab_id,
    drug_codes = drug_codes,
    output_dir = output_dir,
    output_files = existing_files(expected_files),
    n_before_mad = nrow(measurements_before),
    n_after_mad = nrow(measurements_after),
    config_path = normalizePath(config_path, mustWork = TRUE)
  )
})

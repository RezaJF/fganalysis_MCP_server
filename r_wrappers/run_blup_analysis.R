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
  output_dir <- ensure_output_dir(params$output_dir)
  config_path <- params$config_path
  include_sex <- as_scalar_logical(params$include_sex, FALSE)

  conn <- connect_from_config(config_path)

  measurements <- fganalysis::get_measurements_before_drug(
    conn = conn,
    lablist = lab_id,
    druglist = drug_codes,
    months_before = as.numeric(params$months_before %||% 3),
    use_freetext_values = as_scalar_logical(params$use_freetext_values, TRUE),
    use_only_reimbursement = as_scalar_logical(params$use_only_reimbursement, FALSE),
    use_atc_mapping = as_scalar_logical(params$use_atc_mapping, TRUE),
    remove_outliers_sd = as_nullable_numeric(params$remove_outliers_sd),
    winsorize_pct = as_nullable_numeric(params$winsorize_pct)
  )

  if (include_sex && "cov_pheno" %in% names(conn)) {
    covariate_cols <- c("SEX", "SEX_IMPUTED")
    available_cols <- intersect(covariate_cols, colnames(conn$cov_pheno))
    if (length(available_cols) > 0) {
      measurements <- fganalysis::join_covariates_to_labs(
        lab_data = measurements,
        covariates = conn$cov_pheno,
        covariate_cols = available_cols
      )
    }
  }

  blup_results <- fganalysis::calculate_blup_slopes(
    data = measurements,
    output_dir = output_dir,
    min_measurements = as_scalar_integer(params$min_measurements, 2),
    include_sex = include_sex,
    calculate_qc = as_scalar_logical(params$calculate_qc, TRUE),
    save_model = as_scalar_logical(params$save_model, FALSE),
    plot_blup_correlation = as_scalar_logical(params$plot_blup_correlation, FALSE),
    output_file_prefix = params$output_file_prefix %||% NULL
  )

  summary <- fganalysis::summarize_blup_results(blup_results)
  output_files <- existing_files(unlist(lapply(blup_results, function(result) {
    c(result$output_file, result$model_file, result$plot_file)
  }), use.names = FALSE))

  list(
    status = "success",
    lab_id = lab_id,
    drug_codes = drug_codes,
    output_dir = output_dir,
    concepts = as_json_array(names(blup_results)),
    n_concepts = length(blup_results),
    n_measurements = nrow(measurements),
    summary = summary,
    output_files = output_files,
    config_path = normalizePath(config_path, mustWork = TRUE)
  )
})

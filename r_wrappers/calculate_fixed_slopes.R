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
  min_measurements <- as_scalar_integer(params$min_measurements, 2)
  output_dir <- ensure_output_dir(params$output_dir)
  config_path <- params$config_path

  conn <- connect_from_config(config_path)

  measurements <- call_supported(
    fganalysis::get_measurements_before_drug,
    conn = conn,
    lablist = lab_id,
    druglist = drug_codes,
    months_before = months_before,
    use_freetext_values = as_scalar_logical(params$use_freetext_values, TRUE),
    use_only_reimbursement = as_scalar_logical(params$use_only_reimbursement, FALSE),
    use_atc_mapping = as_scalar_logical(params$use_atc_mapping, TRUE),
    remove_outliers_sd = as_nullable_numeric(params$remove_outliers_sd),
    winsorize_pct = as_nullable_numeric(params$winsorize_pct)
  )

  output_files <- character()
  results_per_concept <- list()
  for (concept_id in unique(measurements$OMOP_CONCEPT_ID)) {
    concept_data <- measurements %>%
      dplyr::filter(.data$OMOP_CONCEPT_ID == concept_id)

    slopes <- fganalysis::calculate_fixed_slopes(
      data = concept_data,
      min_measurements = min_measurements
    )

    file_prefix <- params$output_file_prefix %||% as.character(concept_id)
    output_file <- file.path(
      output_dir,
      paste0(file_prefix, "_", concept_id, "_DF13_fixed_slopes.tsv")
    )
    utils::write.table(
      data.frame(FID = slopes$FINNGENID, IID = slopes$FINNGENID,
                 fixed_slope = slopes$fixed_slope),
      file = output_file, sep = "\t", row.names = FALSE, quote = FALSE
    )
    output_files <- c(output_files, normalizePath(output_file, mustWork = TRUE))
    results_per_concept[[as.character(concept_id)]] <- list(
      n_individuals = nrow(slopes),
      mean_slope = mean(slopes$fixed_slope, na.rm = TRUE),
      sd_slope = sd(slopes$fixed_slope, na.rm = TRUE)
    )
  }

  list(
    status = "success",
    lab_id = lab_id,
    drug_codes = drug_codes,
    output_dir = output_dir,
    output_files = output_files,
    concepts = as_json_array(names(results_per_concept)),
    summary = results_per_concept,
    config_path = normalizePath(config_path, mustWork = TRUE)
  )
})

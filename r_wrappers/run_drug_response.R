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
  before_window <- as_numeric_vector(params$before_window, "before_window", 2)
  after_window <- as_numeric_vector(params$after_window, "after_window", 2)
  filter_min_max <- as_numeric_vector(params$filter_min_max %||% c(-Inf, Inf), "filter_min_max", 2)
  output_prefix <- params$output_prefix
  config_path <- params$config_path

  if (is.null(output_prefix) || !nzchar(output_prefix)) {
    stop("output_prefix is required.")
  }
  ensure_parent_dir(output_prefix)

  conn <- connect_from_config(config_path)

  response_data <- call_supported(
    fganalysis::create_drug_response,
    conn = conn,
    lablist = lab_id,
    druglist = drug_codes,
    before_period = before_window,
    after_period = after_window,
    filter_min_max = filter_min_max,
    use_lab_free_text_values = as_scalar_logical(params$use_lab_free_text_values, TRUE),
    use_only_reimbursement_drugs = as_scalar_logical(params$use_only_reimbursement_drugs, FALSE),
    use_atc_mapping = as_scalar_logical(params$use_atc_mapping, TRUE),
    finngen_ids = as_nullable_character_vector(params$finngen_ids),
    remove_outliers_sd = as_nullable_numeric(params$remove_outliers_sd)
  )

  fganalysis::summarize_drug_response(response_data, out_file_prefix = output_prefix)

  upset_plot <- NULL
  if (as_scalar_logical(params$create_upset_plot, FALSE)) {
    fganalysis::summarize_drug_purchases_upset(response_data, out_file_prefix = output_prefix)
    upset_plot <- paste0(output_prefix, "_upset_plot.pdf")
  }

  response_count <- nrow(response_data$responses)
  complete_response_count <- sum(!is.na(response_data$responses$response))
  output_files <- existing_files(c(
    paste0(output_prefix, ".pdf"),
    paste0(output_prefix, "_responses_by_drug.txt"),
    paste0(output_prefix, "_labs_by_time_to_drug.txt"),
    upset_plot
  ))

  list(
    status = "success",
    lab_id = lab_id,
    drug_codes = drug_codes,
    response_count = response_count,
    complete_response_count = complete_response_count,
    output_prefix = output_prefix,
    output_files = output_files,
    config_path = normalizePath(config_path, mustWork = TRUE)
  )
})

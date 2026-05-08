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

  drug_codes <- as_character_vector(params$drug_codes, "drug_codes")
  gap_days <- as.numeric(params$gap_days %||% 30)
  use_pills_per_pack_only <- as_scalar_logical(params$use_pills_per_pack_only, TRUE)
  n_workers <- if (is.null(params$n_workers)) NULL else as.integer(params$n_workers)
  use_atc_mapping <- as_scalar_logical(params$use_atc_mapping, TRUE)
  use_only_reimbursement <- as_scalar_logical(params$use_only_reimbursement, FALSE)
  output_file <- params$output_file %||% NULL
  if (!is.null(output_file)) {
    ensure_parent_dir(output_file)
  }
  config_path <- params$config_path

  conn <- connect_from_config(config_path)
  if (!"vnr" %in% names(conn)) {
    stop("compute_drug_purchase_cadence requires the connection config to include the 'vnr' table.")
  }

  purchases <- fganalysis::get_drug_purchases(
    conn,
    druglist = drug_codes,
    use_only_reimbursement = use_only_reimbursement,
    use_atc_mapping = use_atc_mapping,
    lazy = FALSE
  )

  intervals <- fganalysis::parallel_compute_purchase_frequencies_for_VNRs(
    data = purchases,
    gap = gap_days,
    use_pills_per_pack_only = use_pills_per_pack_only,
    n_workers = n_workers
  )

  cadence_summary <- intervals %>%
    dplyr::group_by(.data$VNR, .data$ATC, .data$medicine) %>%
    dplyr::summarise(
      n_intervals = dplyr::n(),
      median_cadence_days = stats::median(.data$cadence, na.rm = TRUE),
      mean_cadence_days = mean(.data$cadence, na.rm = TRUE),
      sd_cadence_days = stats::sd(.data$cadence, na.rm = TRUE),
      .groups = "drop"
    ) %>%
    dplyr::arrange(dplyr::desc(.data$n_intervals))

  output_files <- character()
  if (!is.null(output_file)) {
    utils::write.table(
      cadence_summary, file = output_file,
      sep = "\t", row.names = FALSE, quote = FALSE
    )
    output_files <- normalizePath(output_file, mustWork = TRUE)
  }
  output_files <- as_json_array(output_files)

  list(
    status = "success",
    drug_codes = drug_codes,
    gap_days = gap_days,
    use_pills_per_pack_only = use_pills_per_pack_only,
    n_intervals = nrow(intervals),
    n_unique_vnrs = length(unique(intervals$VNR)),
    cadence_summary = dataframe_preview(cadence_summary, as_scalar_integer(params$limit, 25)),
    output_files = output_files,
    config_path = normalizePath(config_path, mustWork = TRUE)
  )
})

#!/usr/bin/env Rscript

args_all <- commandArgs(FALSE)
file_arg <- sub("^--file=", "", args_all[grep("^--file=", args_all)][1])
source(file.path(dirname(normalizePath(file_arg)), "common.R"))

run_json_wrapper({
  params <- read_params()

  suppressPackageStartupMessages({
    library(fganalysis)
    library(dplyr)
    library(ggplot2)
  })

  lab_id <- as_character_vector(params$lab_id, "lab_id")
  drug_codes <- as_character_vector(params$drug_codes, "drug_codes")
  before_window <- as_numeric_vector(params$before_window, "before_window", 2)
  after_window <- as_numeric_vector(params$after_window, "after_window", 2)
  output_file <- params$output_file
  config_path <- params$config_path

  if (is.null(output_file) || !nzchar(output_file)) {
    stop("output_file is required.")
  }
  ensure_parent_dir(output_file)

  conn <- connect_from_config(config_path)
  response_data <- fganalysis::create_drug_response(
    conn = conn,
    lablist = lab_id,
    druglist = drug_codes,
    before_period = before_window,
    after_period = after_window,
    use_atc_mapping = as_scalar_logical(params$use_atc_mapping, TRUE)
  )

  plot_data <- response_data$all_measurements %>%
    dplyr::filter(!is.na(.data$first_drug_age), !is.na(.data$VALUE)) %>%
    dplyr::mutate(period = dplyr::case_when(
      dplyr::between(.data$time_to_drug, -before_window[2], -before_window[1]) ~ "Before",
      dplyr::between(.data$time_to_drug, -after_window[2], -after_window[1]) ~ "After",
      TRUE ~ NA_character_
    )) %>%
    dplyr::filter(!is.na(.data$period)) %>%
    dplyr::mutate(period = factor(.data$period, levels = c("Before", "After")))

  if (as_scalar_logical(params$remove_outliers, TRUE) && nrow(plot_data) > 0) {
    plot_data <- plot_data %>%
      dplyr::group_by(.data$first_drug, .data$period) %>%
      dplyr::mutate(
        lower = stats::quantile(.data$VALUE, 0.25, na.rm = TRUE) - 1.5 * stats::IQR(.data$VALUE, na.rm = TRUE),
        upper = stats::quantile(.data$VALUE, 0.75, na.rm = TRUE) + 1.5 * stats::IQR(.data$VALUE, na.rm = TRUE)
      ) %>%
      dplyr::filter(.data$VALUE >= .data$lower, .data$VALUE <= .data$upper) %>%
      dplyr::ungroup()
  }

  if (nrow(plot_data) == 0) {
    stop("No lab measurements fell inside the requested before/after windows.")
  }

  plot <- ggplot2::ggplot(plot_data, ggplot2::aes(x = .data$period, y = .data$VALUE, fill = .data$period)) +
    ggplot2::geom_violin(trim = FALSE, alpha = 0.75) +
    ggplot2::geom_boxplot(width = 0.18, outlier.shape = NA, fill = "white") +
    ggplot2::facet_wrap(~first_drug, scales = "free_y") +
    ggplot2::theme_bw() +
    ggplot2::labs(
      title = "Lab Values Before and After First Drug Purchase",
      x = "Period Relative to Drug Purchase",
      y = "Lab Value"
    ) +
    ggplot2::theme(legend.position = "none")

  ggplot2::ggsave(output_file, plot = plot, width = 10, height = 8)

  list(
    status = "success",
    output_file = normalizePath(output_file, mustWork = TRUE),
    n_plot_rows = nrow(plot_data),
    lab_id = lab_id,
    drug_codes = drug_codes,
    config_path = normalizePath(config_path, mustWork = TRUE)
  )
})

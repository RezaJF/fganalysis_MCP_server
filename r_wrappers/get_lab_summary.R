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
  config_path <- params$config_path
  require_values <- as_scalar_logical(params$require_values, TRUE)
  use_freetext_values <- as_scalar_logical(params$use_freetext_values, TRUE)
  limit <- as_scalar_integer(params$limit, 10)

  conn <- connect_from_config(config_path)
  labs <- fganalysis::get_lab_measurements(
    conn$labs,
    lablist = lab_id,
    require_values = require_values,
    use_freetext_values = use_freetext_values,
    lazy = TRUE
  )

  count_data <- labs %>% dplyr::summarise(n = dplyr::n()) %>% dplyr::collect()
  preview_data <- labs %>% utils::head(limit) %>% dplyr::collect()

  list(
    status = "success",
    lab_id = lab_id,
    count = as.numeric(count_data$n[[1]]),
    preview = preview_data,
    config_path = normalizePath(config_path, mustWork = TRUE)
  )
})

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
  finngen_ids <- as_nullable_character_vector(params$finngen_ids)
  use_only_reimbursement <- as_scalar_logical(params$use_only_reimbursement, FALSE)
  use_atc_mapping <- as_scalar_logical(params$use_atc_mapping, TRUE)
  limit <- as_scalar_integer(params$limit, 10)
  config_path <- params$config_path

  conn <- connect_from_config(config_path)
  drugs <- call_supported(
    fganalysis::get_drug_purchases,
    conn,
    druglist = drug_codes,
    finngen_ids = finngen_ids,
    use_only_reimbursement = use_only_reimbursement,
    use_atc_mapping = use_atc_mapping,
    lazy = TRUE
  )

  count_data <- drugs %>% dplyr::summarise(n = dplyr::n()) %>% dplyr::collect()
  preview_data <- drugs %>% utils::head(limit) %>% dplyr::collect()

  expanded_codes <- tryCatch(
    call_supported(
      fganalysis::expand_atc_codes,
      drug_codes,
      include_hierarchical = FALSE,
      verbose = FALSE,
      require_mapping = use_atc_mapping
    ),
    error = function(e) drug_codes
  )

  list(
    status = "success",
    drug_codes = as_json_array(drug_codes),
    expanded_drug_codes = as_json_array(expanded_codes),
    count = as.numeric(count_data$n[[1]]),
    preview = preview_data,
    config_path = normalizePath(config_path, mustWork = TRUE)
  )
})

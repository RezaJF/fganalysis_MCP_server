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
  first_purch <- call_supported(
    fganalysis::get_first_purchase,
    conn,
    druglist = drug_codes,
    finngen_ids = finngen_ids,
    use_only_reimbursement = use_only_reimbursement,
    use_atc_mapping = use_atc_mapping,
    lazy = FALSE
  )

  list(
    status = "success",
    drug_codes = drug_codes,
    n_individuals = nrow(first_purch),
    preview = dataframe_preview(first_purch, limit),
    config_path = normalizePath(config_path, mustWork = TRUE)
  )
})

#!/usr/bin/env Rscript

args_all <- commandArgs(FALSE)
file_arg <- sub("^--file=", "", args_all[grep("^--file=", args_all)][1])
source(file.path(dirname(normalizePath(file_arg)), "common.R"))

run_json_wrapper({
  suppressPackageStartupMessages({
    library(fganalysis)
  })

  fganalysis::clear_atc_cache()

  list(status = "success", cleared = TRUE)
})

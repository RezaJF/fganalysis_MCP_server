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

  code <- params$code
  if (is.null(code) || !nzchar(code)) {
    stop("code is required.")
  }

  conn <- connect_from_config(params$config_path)
  env <- new.env(parent = globalenv())
  env$conn <- conn

  for (name in getNamespaceExports("fganalysis")) {
    assign(name, getExportedValue("fganalysis", name), envir = env)
  }

  value <- eval(parse(text = code), envir = env)

  serialisable_value <- tryCatch(
    jsonlite::fromJSON(jsonlite::toJSON(value, auto_unbox = TRUE, dataframe = "rows", null = "null", na = "null")),
    error = function(e) {
      list(
        class = class(value),
        message = "Return value could not be serialised to JSON; inspect stdout instead."
      )
    }
  )

  list(
    status = "success",
    result = serialisable_value,
    result_class = class(value),
    config_path = normalizePath(params$config_path, mustWork = TRUE)
  )
})
